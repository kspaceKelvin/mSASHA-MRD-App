#  Multi-parametric T<sub>1</sub> and T<sub>2</sub> with mSASHA

This repository provides a reference implementation of the 3-parameter mSASHA model proposed by Chow K *et al* in [Improved accuracy and precision with three-parameter simultaneous myocardial T<sub>1</sub> and T<sub>2</sub> mapping using multiparametric SASHA](https://onlinelibrary.wiley.com/doi/abs/10.1002/mrm.29170).  A 4-parameter model as described by Akçakaya M *et al* in [Joint Myocardial T<sub>1</sub> and T<sub>2</sub> Mapping Using a Combination of Saturation Recovery and T<sub>2</sub>-preparation](https://onlinelibrary.wiley.com/doi/10.1002/mrm.25975).

## Input Data
This app takes as input a series of T<sub>1</sub>- and T<sub>2</sub>-weighted images and outputs the corresponding T<sub>1</sub> and T<sub>2</sub> maps calculated using a 3-parameter or 4-parameter model.  Images must be from a single 2D slice with preparation times stored in the [MRD XML Header](https://ismrmrd.readthedocs.io/en/latest/mrd_header.html).  Specifically, the following [userParameters](https://github.com/ismrmrd/ismrmrd/blob/master/schema/ismrmrd.xsd) must be present:
* ``timeToCenter`` is a ``<userParameterDouble>`` that specifies the time (in ms) from the start of the single-shot image acquisition to the center line of k-space
* ``TS_x`` is a ``<userParameterDouble>`` that specifies the saturation recovery time for the ``x``th image, where ``x`` is between 1 and the total number of images.  For T<sub>1</sub>-weighted images, TS is defined as the time from the end of the saturation pulse to the beginning of the single-shot acquisition.  For T<sub>1</sub>- and T<sub>2</sub>-weighted images, TS is defined as the time from the end of the saturation pulse to the beginning of the T<sub>2</sub>-preparation module.  For non-prepared (anchor) images, TS is a very large number.
* ``TE_x`` is a ``<userParameterDouble>`` that specifies the T<sub>2</sub>-preparation time for the ``x``th image, where ``x`` is between 1 and the total number of images.  For images without T<sub>2</sub> preparation, the value is 0.

## Supported Configurations
This app supports 2 configs:
* ``mSASHA`` calculates T<sub>1</sub>- and T<sub>2</sub> maps using a 3-parameter model.
* ``jointt1t2_4p`` calculates T<sub>1</sub>- and T<sub>2</sub> maps using a 4-parameter model.

## Running the app
The MRD app can be downloaded from Docker Hub at https://hub.docker.com/r/kspacekelvin/msasha-mrd-app.  In a command prompt on a system with [Docker](https://www.docker.com/) installed, download the Docker image:
```
docker pull kspacekelvin/msasha-mrd-app
```

Start the Docker image and share port 9002:
```
docker run --rm -p 9002:9002 kspacekelvin/msasha-mrd-app
```

In another window, use an MRD client such as the one provided from the [python-ismrmrd-server](https://github.com/kspaceKelvin/python-ismrmrd-server#11-reconstruct-a-phantom-raw-data-set-using-the-mrd-clientserver-pair):

Run the client and send the data to the server.  For 3-parameter model fitting:
```
python3 client.py -o mSASHA_3p_maps.h5 -c mSASHA mSASHA_img.h5
```

For 4-parameter model fitting:
```
python3 client.py -o mSASHA_4p_maps.h5 -c jointt1t2_4p mSASHA_img.h5
```

The output file (e.g. mSASHA_3p_maps.h5) contains the T<sub>1</sub> and T<sub>2</sub> maps (in order) stored in a single series.


## Building the App
This code is intended for use with the [matlab-ismrmrd-server](https://github.com/kspaceKelvin/matlab-ismrmrd-server), which implements an MRD App compatible interface using the [MRD](https://github.com/ismrmrd/ismrmrd/) data format.  The server can be run on any MATLAB-supported operating system, but Docker images can only built when running on Linux.

1. Clone (download) the [matlab-ismrmrd-server](https://github.com/kspaceKelvin/matlab-ismrmrd-server) repository.
    ```
    git clone https://github.com/kspaceKelvin/matlab-ismrmrd-server.git
    ```

1. Clone (download) this repository.
    ```
    git clone https://github.com/kspaceKelvin/mSASHA-MRD-App.git
    ```

1. Merge the MATLAB code from this repository into the main repository.  Note: the ``server.m`` file will be overwritten.
    ```
    cp mSASHA-MRD-App/*.m matlab-ismrmrd-server/
    ```

1. In the MATLAB command prompt, add the ``matlab-ismrmrd-server`` folder and its sub-folders to the path.
    ```
    addpath(genpath('matlab-ismrmrd-server'))
    ```

1. In the MATLAB command prompt, start the server
   ```
   fire_matlab_ismrmrd_server
   ```

1. Send data to the server using the client (see above) to verify the code is correctly installed.

1. Compile the server as a standalone executable and build the Docker image:
    ```  
    res = compiler.build.standaloneApplication('fire_matlab_ismrmrd_server.m', 'TreatInputsAsNumeric', 'on')
    opts = compiler.package.DockerOptions(res, 'ImageName', 'mSASHA-mrd-app')
    compiler.package.docker(res, 'Options', opts)
    ```
