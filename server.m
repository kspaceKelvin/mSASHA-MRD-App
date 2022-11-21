classdef server < handle

    properties
        port           = [];
        tcpHandle      = [];
        log            = [];
        savedata       = false;
        savedataFolder = '';
    end

    methods
        function obj = server(port, log, savedata, savedataFolder)
            log.info('Starting server and listening for data at %s:%d', '0.0.0.0', port);

            if (savedata)
                log.info("Saving incoming data is enabled.")
            end

            obj.port           = port;
            obj.log            = log;
            obj.savedata       = savedata;
            obj.savedataFolder = savedataFolder;
        end

        function serve(obj)
            while true
                try
                    obj.tcpHandle = tcpip('0.0.0.0',          obj.port, ...
                                          'NetworkRole',      'server', ...
                                          'InputBufferSize',  32 * 2^20 , ...
                                          'OutputBufferSize', 32 * 2^20, ...
                                          'Timeout',          3000);  %#ok<TNMLP>  Consider moving toolbox function TCPIP out of the loop for better performance
                    obj.log.info('Waiting for client to connect to this host on port : %d', obj.port);
                    fopen(obj.tcpHandle);
                    obj.log.info('Accepting connection from: %s:%d', obj.tcpHandle.RemoteHost, obj.tcpHandle.RemotePort);
                    handle(obj);
                    flushoutput(obj.tcpHandle);
                    fclose(obj.tcpHandle);
                    delete(obj.tcpHandle);
                    obj.tcpHandle = [];
                catch ME
                    if ~isempty(obj.tcpHandle)
                        fclose(obj.tcpHandle);
                        delete(obj.tcpHandle);
                        obj.tcpHandle = [];
                    end

                    obj.log.error(sprintf('%s\nError in %s (%s) (line %d)', ME.message, ME.stack(1).('name'), ME.stack(1).('file'), ME.stack(1).('line')));
                end
                pause(1)
            end
        end

        function handle(obj)
            try
                conn = connection(obj.tcpHandle, obj.log, obj.savedata, '', obj.savedataFolder);
                config = next(conn);
                metadata = next(conn);

                try
                    metadata = ismrmrd.xml.deserialize(metadata);
                    if ~isempty(metadata.acquisitionSystemInformation.systemFieldStrength_T)
                        obj.log.info("Data is from a %s %s at %1.1fT", metadata.acquisitionSystemInformation.systemVendor, metadata.acquisitionSystemInformation.systemModel, metadata.acquisitionSystemInformation.systemFieldStrength_T)
                    end
                catch
                    obj.log.info("Metadata is not a valid MRD XML structure.  Passing on metadata as text")
                end

                % Decide what program to use based on config
                % As a shortcut, we accept the file name as text too.
                if strcmpi(config, "simplefft")
                    obj.log.info("Starting simplefft processing based on config")
                    recon = simplefft;
                elseif strcmpi(config, "invertcontrast")
                    obj.log.info("Starting invertcontrast processing based on config")
                    recon = invertcontrast;
                elseif strcmpi(config, "mapvbvd")
                    obj.log.info("Starting mapvbvd processing based on config")
                    recon = fire_mapVBVD;
                elseif strcmpi(config, "msasha") || strcmpi(config, "jointt1t2_4p")
                    obj.log.info("Starting mapvbvd processing based on config")
                    recon = mSASHA;
                elseif strcmpi(config, "savedataonly")
                    % Dummy loop with no processing
                    try
                        while true
                            item = next(conn);
                            if isempty(item)
                                break;
                            end
                        end
                        conn.send_close();
                    catch
                        conn.send_close();
                    end
                    % Dummy function for below as we already processed the data
                    recon = @(conn, config, meta, log) (true);
                else
                    if exist(config, 'class')
                        obj.log.info("Starting %s processing based on config", config)
                        eval(['recon = ' config ';'])
                    else
                        obj.log.info("Unknown config '%s'.  Falling back to 'invertcontrast'", config)
                        recon = invertcontrast;
                    end
                end
                recon.process(conn, config, metadata, obj.log);

            catch ME
                obj.log.error('[%s:%d] %s', ME.stack(2).name, ME.stack(2).line, ME.message);
                rethrow(ME);
            end

            if (conn.savedata)
                % Dataset may not be closed properly if a close message is not received
                if (~isempty(conn.dset) && H5I.is_valid(conn.dset.fid))
                    conn.dset.close()
                end

                if (isempty(conn.savedataFile) && exist(conn.mrdFilePath, 'file'))
                    try
                        % Rename the saved file to use the protocol name
                        info = h5info(conn.mrdFilePath);
                        
                        % Check if the group exists
                        indGroup = find(strcmp(arrayfun(@(x) x.Name, info.Groups, 'UniformOutput', false), strcat('/', conn.savedataGroup)), 1);
                        
                        % Check if xml exists
                        xmlExists = any(strcmp(arrayfun(@(x) x.Name, info.Groups(indGroup).Datasets, 'UniformOutput', false), 'xml'));

                        if (xmlExists)
                            dset = ismrmrd.Dataset(conn.mrdFilePath, conn.savedataGroup);
                            xml  = dset.readxml();
                            dset.close();
                            mrdHead = ismrmrd.xml.deserialize(xml);
                            
                            if ~isempty(mrdHead.measurementInformation.protocolName)
                                newFilePath = strrep(conn.mrdFilePath, 'MRD_input_', strcat(mrdHead.measurementInformation.protocolName, '_'));
                                movefile(conn.mrdFilePath, newFilePath);
                                conn.mrdFilePath = newFilePath;
                            end
                        end
                    catch
                        obj.log.error('Failed to rename saved file %s', conn.mrdFilePath);
                    end
                end

                if ~isempty(conn.mrdFilePath)
                    obj.log.info("Incoming data was saved at %s", conn.mrdFilePath)
                end
            end
        end

        function delete(obj)
            if ~isempty(obj.tcpHandle)
                fclose(obj.tcpHandle);
                delete(obj.tcpHandle);
                obj.tcpHandle = [];
            end
        end

    end

end
