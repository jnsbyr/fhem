Modules for the FHEM SmartHome Server
=====================================

This repository contains several modules for the [FHEM SmartHome Server](https://fhem.de/). Some of these modules are development versions of the FHEM distro modules while other modules are add-ons that are not part of the FHEM distro.

### Weather module for forecast data and alerts provided by the [Deutsche Wetterdienst (DWD) OpenData Server](https://www.dwd.de/DE/leistungen/opendata/opendata.html)

#### Features
   - asynchronous http download
   - asynchronous alerts preprocessing and caching
   - CSV parser for forecast
   - XML parser for alerts
   - timezone conversion
   - localized weekday names

#### Installation and Configuration
The built-in module help (Commandref) provides detailed information on the installation and configuration of the module. A step-by-step guide in German language can be found in the [FHEM Wiki](https://wiki.fhem.de/wiki/DWD_OpenData).

#### Discussions
A discussion about the introduction of the module to FHEM can be found in the [FHEM forum](https://forum.fhem.de/index.php/topic,83097.0.html).

#### Status
   - FHEM distro module
   
#### File
   - [55_DWD_OpenData.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/55_DWD_OpenData.pm)


### Widget for displaying forecast data and alerts from the [DWD_OpenData module](https://github.com/jnsbyr/fhem/blob/master/FHEM/55_DWD_OpenData.pm) with [FHEMWeb](https://wiki.fhem.de/wiki/FHEMWEB).

#### Features
This module is a HTML generator to be used with FHEMWeb to display the forcecast data and alerts retrieved by the DWD_OpenData module in graphical form using the FHEM built-in weather icons. For each day 2 icons are shown. The number of days to be displayed can be configured. In case of a weather alert an alert icon is shown on top of the corresponding weather icon. Clicking or touching the alert icon will open a dialog showing alert details.

#### Installation and Configuration
Informations on the installation and configuration can be found in the in-line documentation at end of the source file.

#### Status
   - add-on module
   
#### File
   - [DWDODweblink.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/DWDODweblink.pm)
   

## Copyright and License ##

Copyright and license vary depending on the module, check the module source files for details.