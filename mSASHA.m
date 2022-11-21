classdef mSASHA < handle
    % Linting warning suppression:
    %#ok<*INUSD>  Input argument '' might be unused.  If this is OK, consider replacing it by ~
    %#ok<*NASGU>  The value assigned to variable '' might be unused.
    %#ok<*INUSL>  Input argument '' might be unused, although a later one is used.  Ronsider replacing it by ~
    %#ok<*AGROW>  The variable '' appear to change in size on every loop  iteration. Consider preallocating for speed.

    methods
        function process(obj, connection, config, metadata, logging)
            logging.info('Config: \n%s', config);

            % Continuously parse incoming data parsed from MRD messages
            acqGroup = cell(1,0); % ismrmrd.Acquisition;
            imgGroup = cell(1,0); % ismrmrd.Image;
            try
                while true
                    item = next(connection);

                    % ----------------------------------------------------------
                    % Raw k-space data messages
                    % ----------------------------------------------------------
                    if isa(item, 'ismrmrd.Acquisition')
                        % This module does not support raw k-space reconstruction
                        continue

                    % ----------------------------------------------------------
                    % Image data messages
                    % ----------------------------------------------------------
                    elseif isa(item, 'ismrmrd.Image')
                        % Accumulate all images for one-time processing at the end
                        imgGroup{end+1} = item;

                    elseif isempty(item)
                        break;

                    else
                        logging.error("Unhandled data type: %s", class(item))
                    end
                end
            catch ME
                logging.error(sprintf('%s\nError in %s (%s) (line %d)', ME.message, ME.stack(1).('name'), ME.stack(1).('file'), ME.stack(1).('line')));
            end

            % Process any remaining groups of raw or image data.  This can 
            % happen if the trigger condition for these groups are not met.
            % This is also a fallback for handling image data, as the last
            % image in a series is typically not separately flagged.
            if ~isempty(imgGroup)
                logging.info("Processing all images")
                image = obj.process_images(imgGroup, config, metadata, logging);
                logging.debug("Sending image to client")
                connection.send_image(image);
                imgGroup = cell(1,0);
            end

            connection.send_close();
            return
        end

        function image = process_raw(obj, group, config, metadata, logging)
            logging.error('This function should not be called for this analysis')
            image = [];
        end

        function images = process_images(obj, group, config, metadata, logging)
            images = {};
            % Extract timing parameters from metadata
            indsGood = arrayfun(@(x) strcmp(x.name, 'timeToCenter'), metadata.userParameters.userParameterDouble);
            if sum(indsGood) ~= 1
                logging.error('Could not find timeToCenter in metadata')
                return
            else
                timeToCenter = double(metadata.userParameters.userParameterDouble(indsGood).value);
            end

            aTS = nan(1, numel(group));
            aTE = nan(1, numel(group));

            for i = 1:numel(group)
                indsGood = arrayfun(@(x) strcmp(x.name, sprintf('TS_%d',i)), metadata.userParameters.userParameterDouble);
                if sum(indsGood) == 1
                    aTS(i) = double(metadata.userParameters.userParameterDouble(indsGood).value);
                end

                indsGood = arrayfun(@(x) strcmp(x.name, sprintf('TE_%d',i)), metadata.userParameters.userParameterDouble);
                if sum(indsGood) == 1
                    aTE(i) = double(metadata.userParameters.userParameterDouble(indsGood).value);
                end
            end

            logging.info('Processing %d images with:', numel(group))
            logging.info('  timeToCenter: %1.2f ms', timeToCenter)
            logging.info('  aTS: %sms', sprintf(' %7.1f ', aTS))
            logging.info('  aTE: %sms', sprintf(' %7.1f ', aTE))

            % Extract image data
            cData = cellfun(@(x) x.data, group, 'UniformOutput', false);
            data = double(cat(3, cData{:}));

            % Calculate pixel map
            t1Map = nan(size(data,1), size(data,2));
            t2Map = nan(size(data,1), size(data,2));

            % if isempty(gcp('nocreate'))
            %     logging.info('Starting parallel processing pool...')
            %     parpool;
            % end

            % warnState = warning(              'off',   'levmar:warning');
            % pctRunOnAll('warnState = warning(''off'', ''levmar:warning'');')
            % warning(                          'off',   'MATLAB:rankDeficientMatrix');
            % pctRunOnAll(            'warning(''off'', ''MATLAB:rankDeficientMatrix'');')

            t = tic;
            if strcmpi(config, "msasha")
                model = 'mSASHA';
                logging.info('Calculating T1/T2 maps with 3-parameter mSASHA model...')
            elseif strcmpi(config, "jointt1t2_4p")
                model = '4p';
                logging.info('Calculating T1/T2 maps with 4-parameter joint T1/T2 model...')
            else
                logging.error('Could not determine fitting model from config')
                return
            end
            
            for i = 1:size(data,1)
                % parfor j = 1:size(data,2)
                for j = 1:size(data,2)
                    [~, ~, A, ~] = CalcT1T2(aTS, aTE, timeToCenter, reshape(data(i,j,:), 1, []), model);
                    t1Map(   i,j) = A(1);
                    t2Map(   i,j) = A(2);
                end
            end
            logging.info('Completed in %1.0f seconds', toc(t))

            % Filter out extreme values
            t1Map((t1Map < 0) | (t1Map > 5000)) = 0;
            t2Map( t2Map < 0                  ) = 0;

            % Convert to integers for DICOM compatibility
            t1Map = uint16(t1Map);
            t2Map = uint16(t2Map*10);  % Scale up by 10 to preserve dynamic range

            % --- Create MRD Image for T1 map ----------------------------------
            t1MapImg = ismrmrd.Image(t1Map);

            % Copy original image header, but keep the new data_type and channels
            newHead = t1MapImg.head;
            t1MapImg.head = group{1}.head;
            t1MapImg.head.data_type = newHead.data_type;
            t1MapImg.head.channels  = newHead.channels;

            % Set metadata
            meta = struct;
            meta.DataRole               = 'Quantitative';
            meta.ImageType              = 'T1MAP';
            meta.ImageProcessingHistory = 'MATLAB';
            meta.WindowCenter           = uint16(1000);
            meta.WindowWidth            = uint16(1000);
            meta.ImageRowDir            = group{1}.head.read_dir;
            meta.ImageColumnDir         = group{1}.head.phase_dir;
            meta.Keep_image_geometry    = 1;
            t1MapImg = t1MapImg.set_attribute_string(ismrmrd.Meta.serialize(meta));

            images{end+1} = t1MapImg;

            % --- Create MRD Image for T2 map ----------------------------------
            t2MapImg = ismrmrd.Image(t2Map);

            % Copy original image header, but keep the new data_type and channels
            newHead = t2MapImg.head;
            t2MapImg.head = group{1}.head;
            t2MapImg.head.data_type = newHead.data_type;
            t2MapImg.head.channels  = newHead.channels;

            % Set metadata
            meta = struct;
            meta.DataRole               = 'Quantitative';
            meta.ImageType              = 'T2MAP';
            meta.ImageProcessingHistory = 'MATLAB';
            meta.WindowCenter           = uint16(1000);
            meta.WindowWidth            = uint16(1000);
            meta.ImageRowDir            = group{1}.head.read_dir;
            meta.ImageColumnDir         = group{1}.head.phase_dir;
            meta.Keep_image_geometry    = 1;
            t2MapImg = t2MapImg.set_attribute_string(ismrmrd.Meta.serialize(meta));

            images{end+1} = t2MapImg;
        end
    end
end
