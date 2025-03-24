Modules for the FHEM SmartHome Server
=====================================

This repository contains several modules for the [FHEM SmartHome Server](https://fhem.de/). Some of these modules are development versions of the FHEM distro modules while other modules are add-ons that are not part of the FHEM distro.

- [Gardena 1251 irrigation valve management](#gardena-01251-irrigation-valve-management)
- [rtl_433 wrapper](#rtl_433-wrapper)
- [Firmata modules](#firmata-modules)
- [Weather module for DWD](#weather-module-for-dwd)
- [Widget for DWD weather module](#widget-for-dwd-weather-module)
- [Roller Shutter Controller](#roller-shutter-controller)


## Gardena 01251 irrigation valve management

These two modules allow managing multiple Gardena 01251 irrigation valves using the [esp8266-gardena1251](https://github.com/jnsbyr/esp8266-gardena1251) WiFi controller.

#### Features
- automatic and manual control
- status monitoring
- schedule uploading
- battery voltage measurement calibration
- timer calibration
- irrigation amount estimation

#### Installation and Configuration
The built-in module help (Commandref) provides information on the installation and configuration of the modules. You can use Pod2Html (e.g. at https://metacpan.org/pod2html) to preview the module help.

#### Status
- add-on modules

#### Files
- [68_GardenaBridge.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/68_GardenaBridge.pm)
- [69_GardenaValve.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/69_GardenaValve.pm)


## rtl_433 wrapper

Run [rtl_433](https://github.com/merbanan/rtl_433) to receive data from 433 MHz sensors using a RTL2832 USB stick and convert the output of the rtl_433 process into FHEM readings.

#### Features
- pass arbitrary command line arguments to rtl_433
- run rtl_433 asynchronously
- decode rtl_433 output into readings using regexp

#### Installation and Configuration
The built-in module help (Commandref) provides essential information on the installation and configuration of the module. You can use Pod2Html (e.g. at https://metacpan.org/pod2html) to preview the module help.

#### Status
- add-on module

#### File
- [40_RTL433.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/40_RTL433.pm)


## Firmata modules

Support for [Firmata](https://github.com/firmata/protocol) devices was originally introduced to FHEM by [ntruchess](https://github.com/ntruchsess). This collection of modules is based on the version maintained by ntruchess until 2014.

#### Installation and Configuration
The built-in module help (Commandref) provides essential information on the installation and configuration of the module.

#### Discussions
A discussion about the modules can be found in the [FHEM Forum](https://forum.fhem.de/index.php/topic,81815.120.html).

#### Status
- FHEM distro modules

#### Files
- [10_FRM.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/10_FRM.pm)
- [20_FRM_AD.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/20_FRM_AD.pm)
- [20_FRM_I2C.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/20_FRM_I2C.pm)
- [20_FRM_IN.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/20_FRM_IN.pm)
- [20_FRM_OUT.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/20_FRM_OUT.pm)
- [20_FRM_PWM.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/20_FRM_PWM.pm)
- [20_FRM_RGB.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/20_FRM_RGB.pm)
- [20_FRM_ROTENC.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/20_FRM_ROTENC.pm)
- [20_FRM_SERVO.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/20_FRM_SERVO.pm)
- [20_FRM_STEPPER.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/20_FRM_STEPPER.pm)


## Weather module for DWD

Weather module for forecast data and alerts provided by the [Deutsche Wetterdienst (DWD) OpenData Server](https://www.dwd.de/DE/leistungen/opendata/opendata.html)

#### Features
- asynchronous http download
- asynchronous alerts preprocessing and caching
- XML parser for forecast and alerts
- timezone conversion
- localized weekday names

#### Installation and Configuration
The built-in module help (Commandref) provides detailed information on the installation and configuration of the module. You can use Pod2Html (e.g. at https://metacpan.org/pod2html) to preview the module help. A step-by-step guide in German language can be found in the [FHEM Wiki](https://wiki.fhem.de/wiki/DWD_OpenData).

#### Discussions
An ongoing discussion about the module can be found in the [FHEM Forum](https://forum.fhem.de/index.php/topic,83097.0.html).

#### Status
- FHEM distro module

#### File
- [55_DWD_OpenData.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/55_DWD_OpenData.pm)


## Widget for DWD weather module

Widget for displaying forecast data and alerts from the [DWD_OpenData module](https://github.com/jnsbyr/fhem/blob/master/FHEM/55_DWD_OpenData.pm) with [FHEMWeb](https://wiki.fhem.de/wiki/FHEMWEB).

#### Features
This module is a HTML generator to be used with FHEMWeb to display the forecast data and alerts retrieved by the DWD_OpenData module in graphical form using the FHEM built-in weather icons. For each day 2 icons are shown. The number of days to be displayed can be configured. In case of a weather alert an alert icon is shown on top of the corresponding weather icon. Clicking or touching the alert icon will open a dialog showing alert details.

#### Installation and Configuration
Informations on the installation and configuration can be found in the in-line documentation at end of the source file. You can use Pod2Html (e.g. at https://metacpan.org/pod2html) to preview the module help.

#### Status
- add-on module

#### File
- [99_DWD_OpenData_Weblink.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/99_DWD_OpenData_Weblink.pm)


## Roller Shutter Controller

Module to control a motor driven roller shutter combining comfort and thermal aspects.

#### Features

- support roller shutter actors with a) position, b) up/stop/down and c) up/down control
- time preferences for morning up and evening down
- detect "real" sunrise and sunset via sun luminosity sensor
- partial opening during twilight (visual shielding)
- delayed morning opening on weekend and holidays (sleep in)
- immediate morning opening on motion detection
- door sensor support to prevent closing of roller shutter while doors are open
- indoor/outdoor thermal flow estimation (thermal radiation and sun) and thermal shading to prevent heating
  based on time, luminosity and room temperature providing visual shielding and thermal shielding.

#### Installation and Configuration
The built-in module help (Commandref) provides essential information on the installation and configuration of the module. You can use Pod2Html (e.g. at https://metacpan.org/pod2html) to preview the module help.

#### File
- [98_RollerShutterController.pm](https://github.com/jnsbyr/fhem/blob/master/FHEM/98_RollerShutterController.pm)


## Copyright and License ##

Copyright and license vary depending on the module, check the module source files for details.
