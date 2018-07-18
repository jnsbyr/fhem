# -----------------------------------------------------------------------------
# $Id: DWD_OpenData_Weblink.pm 2.011.003 2018-07-14 18:27:00Z jensb $
# -----------------------------------------------------------------------------

=encoding UTF-8

=head1 NAME

DWD_OpenData_Weblink - A FHEM Perl module to visualize the forecasts data and alerts
of the DWD OpenData module.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015 Jens B.

All rights reserved

This script is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

The GNU General Public License can be found at

http://www.gnu.org/copyleft/gpl.html.

A copy is found in the textfile GPL.txt and important notices to the license
from the author is found in LICENSE.txt distributed with these scripts.

This script is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

This copyright notice MUST APPEAR in all copies of the script!

=cut

package DWD_OpenData_Weblink;

use strict;
use warnings;

use POSIX;
use Time::Piece;
use DateTime;
use Scalar::Util qw(looks_like_number);

# font color configuration
use constant TEMP_FREEZE  => 3;  # < blue
use constant TEMP_WARM    => 25; # > orange
use constant PRECIP_RAIN  => 50; # > blue

use constant COLOR_FREEZE => "blue";    # light background -> blue, dark background -> skyblue
use constant COLOR_WARM   => "orange";
use constant COLOR_RAIN   => "blue";    # light background -> blue, dark background -> skyblue

require Exporter;
our $VERSION   = 2.011.003;
our @ISA       = qw(Exporter);
our @EXPORT    = qw(AsHtmlH);
our @EXPORT_OK = qw();

# weather code to FHEM weather icon name mapping
my @dayWeatherIconMap = ( "na",              # "Bewölkungsentwicklung nicht beobachtet",
                          "na",              # "Bewölkung abnehmend",
                          "na",              # "Bewölkung unverändert",
                          "na",              # "Bewölkung zunehmend",
                          # 4 Dunst, Rauch, Staub oder Sand
                          "fog",             # "Sicht durch Rauch oder Asche vermindert",
                          "haze",            # "trockener Dunst (relative Feuchte < 80 %)",
                          "fog",             # "verbreiteter Schwebstaub, nicht vom Wind herangeführt",
                          "fog",             # "Staub oder Sand bzw. Gischt, vom Wind herangeführt",
                          "fog",             # "gut entwickelte Staub- oder Sandwirbel",
                          "fog",             # "Staub- oder Sandsturm im Gesichtskreis, aber nicht an der Station",
                          # 10 Trockenereignisse
                          "haze",            # "feuchter Dunst (relative Feuchte > 80 %)",
                          "fog",             # "Schwaden von Bodennebel",
                          "fog",             # "durchgehender Bodennebel",
                          "na",              # "Wetterleuchten sichtbar, kein Donner gehört",
                          "na",              # "Niederschlag im Gesichtskreis, nicht den Boden erreichend",
                          "na",              # "Niederschlag in der Ferne (> 5 km), aber nicht an der Station",
                          "na",              # "Niederschlag in der Nähe (< 5 km), aber nicht an der Station",
                          "thunderstorm",    # "Gewitter (Donner hörbar), aber kein Niederschlag an der Station",
                          "na",              # "Markante Böen im Gesichtskreis, aber kein Niederschlag an der Station",
                          "na",              # "Tromben (trichterförmige Wolkenschläuche) im Gesichtskreis",
                          # 20 Ereignisse der letzten Stunde, aber nicht zur Beobachtungszeit
                          "na",              # "nach Sprühregen oder Schneegriesel",
                          "na",              # "nach Regen",
                          "na",              # "nach Schneefall",
                          "na",              # "nach Schneeregen oder Eiskörnern",
                          "na",              # "nach gefrierendem Regen",
                          "na",              # "nach Regenschauer",
                          "na",              # "nach Schneeschauer",
                          "na",              # "nach Graupel- oder Hagelschauer",
                          "na",              # "nach Nebel",
                          "na",              # "nach Gewitter",
                          # 30 Staubsturm, Sandsturm, Schneefegen oder -treiben
                          "na",              # "leichter oder mäßiger Sandsturm, an Intensität abnehmend",
                          "na",              # "leichter oder mäßiger Sandsturm, unveränderte Intensität",
                          "na",              # "leichter oder mäßiger Sandsturm, an Intensität zunehmend",
                          "na",              # "schwerer Sandsturm, an Intensität abnehmend",
                          "na",              # "schwerer Sandsturm, unveränderte Intensität",
                          "na",              # "schwerer Sandsturm, an Intensität zunehmend",
                          "na",              # "leichtes oder mäßiges Schneefegen, unter Augenhöhe",
                          "na",              # "starkes Schneefegen, unter Augenhöhe",
                          "na",              # "leichtes oder mäßiges Schneetreiben, über Augenhöhe",
                          "na",              # "starkes Schneetreiben, über Augenhöhe",
                          # 40 Nebel oder Eisnebel
                          "na",              # "Nebel in einiger Entfernung",
                          "fog",             # "Nebel in Schwaden oder Bänken",
                          "fog",             # "Nebel, Himmel erkennbar, dünner werdend",
                          "fog",             # "Nebel, Himmel nicht erkennbar, dünner werdend",
                          "fog",             # "Nebel, Himmel erkennbar, unverändert",
                          "fog",             # "Nebel, Himmel nicht erkennbar, unverändert",
                          "fog",             # "Nebel, Himmel erkennbar, dichter werdend",
                          "fog",             # "Nebel, Himmel nicht erkennbar, dichter werdend",
                          "fog",             # "Nebel mit Reifansatz, Himmel erkennbar",
                          "fog",             # "Nebel mit Reifansatz, Himmel nicht erkennbar",
                          # 50 Sprühregen
                          "chance_of_rain",  # "unterbrochener leichter Sprühregen",
                          "mist",            # "durchgehend leichter Sprühregen",
                          "chance_of_rain",  # "unterbrochener mäßiger Sprühregen",
                          "mist",            # "durchgehend mäßiger Sprühregen",
                          "chance_of_rain",  # "unterbrochener starker Sprühregen",
                          "mist",            # "durchgehend starker Sprühregen",
                          "mist",            # "leichter gefrierender Sprühregen",
                          "mist",            # "mäßiger oder starker gefrierender Sprühregen",
                          "mist",            # "leichter Sprühregen mit Regen",
                          "mist",            # "mäßiger oder starker Sprühregen mit Regen",
                          # 60 Regen
                          "chance_of_rain",  # "unterbrochener leichter Regen oder einzelne Regentropfen",
                          "rain",            # "durchgehend leichter Regen",
                          "chance_of_rain",  # "unterbrochener mäßiger Regen",
                          "rain",            # "durchgehend mäßiger Regen",
                          "chance_of_rain",  # "unterbrochener starker Regen",
                          "rain",            # "durchgehend starker Regen",
                          "sleet",           # "leichter gefrierender Regen",
                          "sleet",           # "mäßiger oder starker gefrierender Regen",
                          "sleet",           # "leichter Schneeregen",
                          "sleet",           # "mäßiger oder starker Schneeregen",
                          # 70 Schnee
                          "chance_of_snow",  # "unterbrochener leichter Schneefall oder einzelne Schneeflocken",
                          "snow",            # "durchgehend leichter Schneefall",
                          "chance_of_snow",  # "unterbrochener mäßiger Schneefall",
                          "snow",            # "durchgehend mäßiger Schneefall",
                          "chance_of_snow",  # "unterbrochener starker Schneefall",
                          "snow",            # "durchgehend starker Schneefall",
                          "icy",             # "Eisnadeln (Polarschnee)",
                          "snow",            # "Schneegriesel",
                          "snow",            # "Schneekristalle",
                          "icy",             # "Eiskörner (gefrorene Regentropfen)",
                          # 80 Schauer
                          "drizzle",         # "leichter Regenschauer",
                          "drizzle",         # "mäßiger oder starker Regenschauer",
                          "drizzle",         # "äußerst heftiger Regenschauer",
                          "chance_of_sleet", # "leichter Schneeregenschauer",
                          "chance_of_sleet", # "mäßiger oder starker Schneeregenschauer",
                          "chance_of_snow",  # "leichter Schneeschauer",
                          "chance_of_snow",  # "mäßiger oder starker Schneeschauer",
                          "chance_of_snow",  # "leichter Graupelschauer",
                          "chance_of_snow",  # "mäßiger oder starker Graupelschauer",
                          "chance_of_snow",  # "leichter Hagelschauer",
                          "chance_of_snow",  # "mäßiger oder starker Hagelschauer",
                          # 90 Gewitter
                          "chance_of_storm", # "Gewitter in der letzten Stunde, zurzeit leichter Regen",
                          "chance_of_storm", # "Gewitter in der letzten Stunde, zurzeit mäßiger oder starker Regen",
                          "chance_of_storm", # "Gewitter in der letzten Stunde, zurzeit leichter Schneefall/Schneeregen/Graupel/Hagel",
                          "chance_of_storm", # "Gewitter in der letzten Stunde, zurzeit mäßiger oder starker Schneefall/Schneeregen/Graupel/Hagel",
                          "thunderstorm",    # "leichtes oder mäßiges Gewitter mit Regen oder Schnee",
                          "thunderstorm",    # "leichtes oder mäßiges Gewitter mit Graupel oder Hagel",
                          "thunderstorm",    # "starkes Gewitter mit Regen oder Schnee",
                          "thunderstorm",    # "starkes Gewitter mit Sandsturm",
                          "thunderstorm"     # "starkes Gewitter mit Graupel oder Hagel",);
                        );

my @NightWeatherIconMap = ( "na",                    # "Bewölkungsentwicklung nicht beobachtet",
                            "na",                    # "Bewölkung abnehmend",
                            "na",                    # "Bewölkung unverändert",
                            "na",                    # "Bewölkung zunehmend",
                            # 4 Dunst, Rauch, Staub oder Sand
                            "fog",                   # "Sicht durch Rauch oder Asche vermindert",
                            "haze_night",            # "trockener Dunst (relative Feuchte < 80 %)",
                            "fog",                   # "verbreiteter Schwebstaub, nicht vom Wind herangeführt",
                            "fog",                   # "Staub oder Sand bzw. Gischt, vom Wind herangeführt",
                            "fog",                   # "gut entwickelte Staub- oder Sandwirbel",
                            "fog",                   # "Staub- oder Sandsturm im Gesichtskreis, aber nicht an der Station",
                            # 10 Trockenereignisse
                            "haze_night",            # "feuchter Dunst (relative Feuchte > 80 %)",
                            "fog",                   # "Schwaden von Bodennebel",
                            "fog",                   # "durchgehender Bodennebel",
                            "na",                    # "Wetterleuchten sichtbar, kein Donner gehört",
                            "na",                    # "Niederschlag im Gesichtskreis, nicht den Boden erreichend",
                            "na",                    # "Niederschlag in der Ferne (> 5 km), aber nicht an der Station",
                            "na",                    # "Niederschlag in der Nähe (< 5 km), aber nicht an der Station",
                            "thunderstorm",          # "Gewitter (Donner hörbar), aber kein Niederschlag an der Station",
                            "na",                    # "Markante Böen im Gesichtskreis, aber kein Niederschlag an der Station",
                            "na",                    # "Tromben (trichterförmige Wolkenschläuche) im Gesichtskreis",
                            # 20 Ereignisse der letzten Stunde, aber nicht zur Beobachtungszeit
                            "na",                    # "nach Sprühregen oder Schneegriesel",
                            "na",                    # "nach Regen",
                            "na",                    # "nach Schneefall",
                            "na",                    # "nach Schneeregen oder Eiskörnern",
                            "na",                    # "nach gefrierendem Regen",
                            "na",                    # "nach Regenschauer",
                            "na",                    # "nach Schneeschauer",
                            "na",                    # "nach Graupel- oder Hagelschauer",
                            "na",                    # "nach Nebel",
                            "na",                    # "nach Gewitter",
                            # 30 Staubsturm, Sandsturm, Schneefegen oder -treiben
                            "na",                    # "leichter oder mäßiger Sandsturm, an Intensität abnehmend",
                            "na",                    # "leichter oder mäßiger Sandsturm, unveränderte Intensität",
                            "na",                    # "leichter oder mäßiger Sandsturm, an Intensität zunehmend",
                            "na",                    # "schwerer Sandsturm, an Intensität abnehmend",
                            "na",                    # "schwerer Sandsturm, unveränderte Intensität",
                            "na",                    # "schwerer Sandsturm, an Intensität zunehmend",
                            "na",                    # "leichtes oder mäßiges Schneefegen, unter Augenhöhe",
                            "na",                    # "starkes Schneefegen, unter Augenhöhe",
                            "na",                    # "leichtes oder mäßiges Schneetreiben, über Augenhöhe",
                            "na",                    # "starkes Schneetreiben, über Augenhöhe",
                            # 40 Nebel oder Eisnebel
                            "na",                    # "Nebel in einiger Entfernung",
                            "fog",                   # "Nebel in Schwaden oder Bänken",
                            "fog",                   # "Nebel, Himmel erkennbar, dünner werdend",
                            "fog",                   # "Nebel, Himmel nicht erkennbar, dünner werdend",
                            "fog",                   # "Nebel, Himmel erkennbar, unverändert",
                            "fog",                   # "Nebel, Himmel nicht erkennbar, unverändert",
                            "fog",                   # "Nebel, Himmel erkennbar, dichter werdend",
                            "fog",                   # "Nebel, Himmel nicht erkennbar, dichter werdend",
                            "fog",                   # "Nebel mit Reifansatz, Himmel erkennbar",
                            "fog",                   # "Nebel mit Reifansatz, Himmel nicht erkennbar",
                            # 50 Sprühregen
                            "chance_of_rain_night",  # "unterbrochener leichter Sprühregen",
                            "mist",                  # "durchgehend leichter Sprühregen",
                            "chance_of_rain_night",  # "unterbrochener mäßiger Sprühregen",
                            "mist",                  # "durchgehend mäßiger Sprühregen",
                            "chance_of_rain_night",  # "unterbrochener starker Sprühregen",
                            "mist",                  # "durchgehend starker Sprühregen",
                            "mist",                  # "leichter gefrierender Sprühregen",
                            "mist",                  # "mäßiger oder starker gefrierender Sprühregen",
                            "mist",                  # "leichter Sprühregen mit Regen",
                            "mist",                  # "mäßiger oder starker Sprühregen mit Regen",
                            # 60 Regen
                            "chance_of_rain_night",  # "unterbrochener leichter Regen oder einzelne Regentropfen",
                            "rain",                  # "durchgehend leichter Regen",
                            "chance_of_rain_night",  # "unterbrochener mäßiger Regen",
                            "rain",                  # "durchgehend mäßiger Regen",
                            "chance_of_rain_night",  # "unterbrochener starker Regen",
                            "rain",                  # "durchgehend starker Regen",
                            "sleet",                 # "leichter gefrierender Regen",
                            "sleet",                 # "mäßiger oder starker gefrierender Regen",
                            "sleet",                 # "leichter Schneeregen",
                            "sleet",                 # "mäßiger oder starker Schneeregen",
                            # 70 Schnee
                            "chance_of_snow",        # "unterbrochener leichter Schneefall oder einzelne Schneeflocken",
                            "snow",                  # "durchgehend leichter Schneefall",
                            "chance_of_snow",        # "unterbrochener mäßiger Schneefall",
                            "snow",                  # "durchgehend mäßiger Schneefall",
                            "chance_of_snow",        # "unterbrochener starker Schneefall",
                            "snow",                  # "durchgehend starker Schneefall",
                            "icy",                   # "Eisnadeln (Polarschnee)",
                            "snow",                  # "Schneegriesel",
                            "snow",                  # "Schneekristalle",
                            "icy",                   # "Eiskörner (gefrorene Regentropfen)",
                            # 80 Schauer
                            "drizzle_night",         # "leichter Regenschauer",
                            "drizzle_night",         # "mäßiger oder starker Regenschauer",
                            "drizzle_night",         # "äußerst heftiger Regenschauer",
                            "chance_of_sleet",       # "leichter Schneeregenschauer",
                            "chance_of_sleet",       # "mäßiger oder starker Schneeregenschauer",
                            "chance_of_snow",        # "leichter Schneeschauer",
                            "chance_of_snow",        # "mäßiger oder starker Schneeschauer",
                            "chance_of_snow",        # "leichter Graupelschauer",
                            "chance_of_snow",        # "mäßiger oder starker Graupelschauer",
                            "chance_of_snow",        # "leichter Hagelschauer",
                            "chance_of_snow",        # "mäßiger oder starker Hagelschauer",
                            # 90 Gewitter
                            "chance_of_storm_night", # "Gewitter in der letzten Stunde, zurzeit leichter Regen",
                            "chance_of_storm_night", # "Gewitter in der letzten Stunde, zurzeit mäßiger oder starker Regen",
                            "chance_of_storm_night", # "Gewitter in der letzten Stunde, zurzeit leichter Schneefall/Schneeregen/Graupel/Hagel",
                            "chance_of_storm_night", # "Gewitter in der letzten Stunde, zurzeit mäßiger oder starker Schneefall/Schneeregen/Graupel/Hagel",
                            "thunderstorm",          # "leichtes oder mäßiges Gewitter mit Regen oder Schnee",
                            "thunderstorm",          # "leichtes oder mäßiges Gewitter mit Graupel oder Hagel",
                            "thunderstorm",          # "starkes Gewitter mit Regen oder Schnee",
                            "thunderstorm",          # "starkes Gewitter mit Sandsturm",
                            "thunderstorm"           # "starkes Gewitter mit Graupel oder Hagel",);
                          );

# icon parameters
use constant ICONHIGHT => 120;
use constant ICONWIDTH => 175;
use constant ICONSCALE => 0.5;

# get CSS style
sub GetCSS() {
  my $style = '
  <style type="text/css">
    /* weather table with fixed column width */
    .weatherForecast {
        display: table;
        table-layout: fixed;
        column-gap: 10px;
    }
    /* weather table header row */
    .weatherHeaderRow {
        display: table-header-group;
        white-space: nowrap;
    }
    /* weather table data row */
    .weatherDataRow {
        display: table-row-group;
    }
    /* weather table data cells */
    #weatherFontBold {
        font-weight: bold;
    }
    .weatherWeekday {
        display: table-cell;
        min-width: 70px;
        text-align: center;
        vertical-align: middle;
    }
    .weatherCondition {
        display: table-cell;
        position: relative;
        top: -4px;
        text-align: center;
        vertical-align: middle;
        font-size: 60%;
        word-wrap: break-word;
    }
    .weatherTemperature {
        display: table-cell;
        text-align: center;
        vertical-align: middle;
        font-size: 95%;
        white-space: nowrap;
    }
    .weatherWind {
        display: table-cell;
        text-align: center;
        vertical-align: middle;
        font-size: 80%;
        padding-top: 3px;
    }
    /* weather table condition icon cell */
    .weatherIcon {
        display: table-cell;
        position: relative;
        text-align: center;
    }
    /* weather icon */
    .weatherIcon img {
        width: 96%;
        height: auto;
        position: relative;
    }
    /* embedded alert icon with pointer support */
    .weatherAlertIcon {
        position: absolute;
        top: 5px;
        right: 5px;
        width: 25px;
        height: 22px;
        background-size: 25px 22px;
        background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAkCAMAAADM4ogkAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAyppVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMy1jMDExIDY2LjE0NjcyOSwgMjAxMi8wNS8wMy0xMzo0MDowMyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIEVsZW1lbnRzIDEyLjAgV2luZG93cyIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDo1RjU1NzJBRDMyRTcxMUU1QTk4MkI0RTkwODEwODQ1QSIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDo1RjU1NzJBRTMyRTcxMUU1QTk4MkI0RTkwODEwODQ1QSI+IDx4bXBNTTpEZXJpdmVkRnJvbSBzdFJlZjppbnN0YW5jZUlEPSJ4bXAuaWlkOjVGNTU3MkFCMzJFNzExRTVBOTgyQjRFOTA4MTA4NDVBIiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOjVGNTU3MkFDMzJFNzExRTVBOTgyQjRFOTA4MTA4NDVBIi8+IDwvcmRmOkRlc2NyaXB0aW9uPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiA8P3hwYWNrZXQgZW5kPSJyIj8+oFydjAAAAwBQTFRF9fX267W51Csy9d7c1VBV9uPc/vz89+nl5YB/2Flk2mZp1Cgv0Csw5pWR7K2t1Soy1Cow7b6y0iUr+/r61jI54X+A+uvq21xV44qO/fj400tU1kxG3nNx2mJp34Bz/Pj2a2tr4Ht91S43fn5+1jA31S0y0iYu1TA1/ff3+/TxEhIS3W1u1jA010Q++efj1kVH1Tk+gYGB6qWh4oWEtra21TI48sjH1VVc1tbW1jY22ltd4YF/1kFHl5eX/vz7/Pz84nZt+evt9+Tm2mNu1Sw14YSD1Ss04YKC0isv4X5/0zc21CUu8cnL0jA20jAz22xy1jE422Zv1i800isw1Cgx11xjKysr1FFZ4X190iQsGRkZ0jY+1TE41Cww0y0y0ykt1i431i4z0y800ikvPz4/AAAA////DQwM1TI30yYs1TE31TA21TE21S401S801S810ycs//7+1TA3///+/v791TI2/v//0Sov0iYt0yYt6urqkZGR1TM40ycu1S414ODg4YB3+/Hw7bK0/vv78fHxh4eH+OPf0i8w1DI30icu1y843Zia/PX13Nvb6aWZ4YKE+fDv21RT00E83G5y3m9x7tDF3Gdu99fW1EJK1ktK3t7e5I+R4oeH3WNp3oCF+vH16ZOJ1Sw27cG31i018dDL4qOf3Wde7Kqe+O7m2ERH+e3o+u/t4YuY/Pb15IqG5p2R4np52TA82mhx2V1p3mpx5oWL66uiRkZG4YOR/v7+1ygz1TxC8dDV9dHS2VJL1CUw8by79+Hg7bq3vr6+9dnR1Tc49d/X11le77yv22hl2lVY+Ofo33540icspqan+/f49N/h5J6m2HB7zczN3nZ88c3FsrKz3HZ74ICC4YGA1oJy10JD+Onj8c3J1Dk71T494oaE4HpxNTU14XRz7Ozs7+/vcG9v+/bz/Pj1/fr3IiIi676/5IJx4Hpr6amn56On6aGd2mlu4X2A22Vm2WFk1jI33GNk+/Ds2VJU2FZW8/Pz78jD3V1v55iY3W1x////C1yJRAAAAQB0Uk5T////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AFP3ByUAAAMKSURBVHjajNEFWBNxGAbwOXEoUzYnqCgGuPMUUFE8sRuwgDlUEJmK8z6/XWyEEjrswu7u7u7u7u4u7G7FWxoj/J6L9/7v77nnQpTpMM7XFkocV0UOK2VKbkt3/R+4KY0Zlnw8d7ikBeu9VroRcoXPg5F1Y5Mn5wYPaRnGqOxMfPbIGXZfFMxxJGtg0lxzhoWlKpYfSrCd9f4rc4JPKs1l9B1aeabGoLRQTnBxG8T2K2DwLV7FRVTOHi47yKKmxGyAagoGxb7x2cLSMuS0eZIAMopJUaWtkR3M1yUBpe8lkuoj4WYYm8Bf98gaxjdsSik7toKydPQ0OKEzUnGuWcOLWgZPXoCe3Wi6HlS+zVMG/35Zwfq7eqO+wxk4T9N0OYDXKQylnZ4VnKdxM5bfAtDTh6arAlT4IldxXYo6woyS3hwxpRHA12ia7gUA3yKUKL8f7wCPiClMOSsA0VPTMwIkeeoQm+39F1asZECZ02kBFGlH06eEM+Rt0RvFHyX/wNUy7JGex9Q3EGB1U4BCLVXK9D1/wxu1lJS8lMTc36Pp/eZQcaoM9Us9/oSJL8QUGbrDXMNmOvqBJe3TxqC22p/wgIbBlrMsLZSju1pT93dSZDsW/Q3rF/NG3r+xte4zqKY1QY0IBuVvwQ4LazFGUTzRVhexJziahkzyTht8PM6AwXUbWbutj3za2W+5IIxEovYAKxwlww+KV7buYTfzL7TODOGry/tb4KdaCSg/VsFWDfSx/ELLLK9CILl9hBnOEaOq4DN7BZe6lv36++plJ3ST/zDBfEOEN6udBNnNWDHFhTpnihIbNkXKUNfLyyuqeciVOwFvr7oHrApqHhTiPjog6EqdNVFVDIji/JmiiYQbopFM3R0XF6fT6VJ15jFFnUJhSqQRETV5RXfnGykhMea9B2M624ezBaOmuKiv1GDg9TxJ8sIxltB7E0QsT/BqpdrPT9g4P7VaTcZKL4vGDP/psq71BpdSLj9nTmod3mTC+HDfN+FN2jodjlwfGRnoFNg2cH2B7+ca/xJgAFL1l3PxpIx4AAAAAElFTkSuQmCC);
    }
    .weatherAlertIcon:hover {
        opacity: 0.7;
    }
    .weatherAlertIcon:focus {
        opacity: 1.0;
    }
    /* opaque white background for alerts dialog */
    .weatherOverlay {
        display: none;
        position: fixed;
        z-index: 1;
        opacity: 0.2;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: white;
    }
    .weatherAlertIcon:focus .weatherOverlay {
        display: block;
    }
    /* alerts dialog box */
    [class^=weatherAlertBox] {
        display: none;
        position: absolute;
        z-index: 2;
        opacity: 1;
        top: 0;
        border: 3px solid white;
        border-radius:3px;
        box-shadow: 0px 0px 6px 4px #666;
        background: #EEE;
    }
    .weatherAlertIcon:focus .weatherAlertBoxLeft {
        display: block;
        right: -268px;
    }
    .weatherAlertIcon:focus .weatherAlertBoxCenter {
        display: block;
        left: -178px;
    }
    .weatherAlertIcon:focus .weatherAlertBoxRight {
        display: block;
        left: -312px;
    }
    /* alerts dialog close button */
    .weatherAlertsClose {
        position: absolute;
        top: -12px;
        right: -13px;

        border-radius: 12px;
        box-shadow: 1px 1px 3px #666;

        line-height: 21px;
        width: 21px;
        background: #606061;

        text-align: center;
        text-decoration: none;
        font-family: Sans-serif;
        font-weight: bold;
        color: white;
    }
    .weatherAlertsClose:hover {
        opacity: 0.8;
    }
    /* alerts dialog title */
    .weaterAlertsTitle {
        font-weight: bold;
        color: black;
    }
    /* alert messages */
    [class^=weaterAlertMessage] {
        float: left;
        text-align: left;
        white-space: nowrap;
    }
    .weaterAlertMessage p {
        white-space: normal;
    }
  </style>';
  return $style;
}

=head1 MODULE FUNCTIONS

=head2 IsDay($$)

=over

=item * param time:     epoch time

=item * param altitude: see documentation of module SUNRISE_EL

=item * return 1 if sun is up at given time, otherwise 0

=back

note: result is only defined for location defined in FHEM global

=cut

sub IsDay($$) {
  my ($time, $altitude) = @_;

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
  my $t = ($hour*60 + $min)*60 + $sec;

  my (undef, $srHour, $srMin, $srSec, undef) = ::GetTimeSpec(::sunrise_abs_dat($time, $altitude));
  my $sunrise = ($srHour*60 + $srMin)*60 + $srSec;

  my (undef, $ssHour, $ssMin, $ssSec, undef) = ::GetTimeSpec(::sunset_abs_dat($time, $altitude));
  my $sunset = ($ssHour*60 + $ssMin)*60 + $ssSec;

  #Log 3, "IsDay: $hour:$min:$sec  $srHour:$srMin:$srSec $ssHour:$ssMin:$ssSec";

  return $t >= $sunrise && $t <= $sunset;
}

=head2 IsActive($$$)

=over

=item * param start: epoch time range start

=item * param end:   epoch time range end

=item * param time   epoch time

=item * return 1 if time is inside range, otherwise 0

=back

=cut

sub IsActive($$$) {
  my ($start, $end, $time) = @_;

  if ($start && $end) {
    return $time >= $start && $time < $end;
  } else {
    return 0;
  }
}

=head2 IsInRange($$$$)

=over

=item * param start: 1st range start (incl.)

=item * param end:   1st range end   (excl.)

=item * param start: 2nd range start (incl.)

=item * param end:   2nd range end   (excl.)

=item * return 1 if 2nd range overlaps with 1st range, otherwise 0

=back

=cut

sub IsInRange($$$$) {
  my ($start, $end, $iStart, $iEnd) = @_;

  if ($start && $end) {
    return ($iStart < $start && $iEnd >= $end) ||
           ($iStart >= $start && $iStart < $end) ||
           ($iEnd >= $start && $iEnd < $end);
  } else {
    return 0;
  }
}

=head2 GetWeatherIconTag($$;$)

get FHEM weather icon for weather code

=over

=item * param weatherCode

=item * param cloudCover:  [1/8]

=item * param time:        epoch time or undef for day or 1 for night, scalar, optional

=item * return HTML string

=back

=cut

sub GetWeatherIconTag($$;$) {
  my ($weatherCode, $cloudCover, $time) = @_;

  my $day = !defined($time) || ($time > 1 && IsDay($time, "REAL"));

  my $iconName = "na";
  if (defined($weatherCode)) {
    if ($weatherCode < 4  && defined($cloudCover)) {
      # no weather activity, use cloud cover
      if ($cloudCover < 3) {
        $iconName = $day? 'sunny' : 'clear';                     # 012
      } elsif ($cloudCover < 5) {
        $iconName = $day? 'partlycloudy' : 'partlycloudy_night'; # 34
      } elsif ($cloudCover < 7) {
        $iconName = $day? 'mostlycloudy' : 'mostlycloudy_night'; # 56
      } else {
        $iconName = 'overcast';                                  # 789
      }
    } else {
      $iconName = $day? $dayWeatherIconMap[$weatherCode] : $NightWeatherIconMap[$weatherCode];
    }
  }

  if (defined($iconName)) {
    my $url= ::FW_IconURL("weather/$iconName");
    return "<img src=\"$url\" alt=\"$iconName\">";
  } else {
    return "";
  }
}

=head2 ToForecastIndex($$)

icon index, display time offsets and forecast resolution to relative day,
hour index, day prefix and hour prefix for forecast readings access

=over

=item * param iconIndex:      index of display icon starting with -1

=item * param offsets:        array of display time offsets for 1st and 2nd icon

=item * param timeResolution: time resolution of forecast readings (3 or 6)

=item * return array of relative day, hour index, day prefix and hour prefix

=back

=cut

sub ToForecastIndex($$$) {
  my ($iconIndex, $offsets, $timeResolution) = @_;

  my $day = int(($iconIndex + 1)/2);
  my $index = 6/$timeResolution*((($iconIndex + 1) % 2) == 0? 1 : 2);
  if ($day == 0) {
    $index += ${$offsets}[$iconIndex + 1];
    if ($index >= 24/$timeResolution) {
      $day++;
      $index -= 24/$timeResolution;
    }
  }
  my $dayPrefix = "fc".$day;
  my $hourPrefix = $dayPrefix."_".$index;

  my @result;
  push(@result, $day);
  push(@result, $index);
  push(@result, $dayPrefix);
  push(@result, $hourPrefix);

  return @result;
}

=head2 AsHtmlH($;$$)

create forecast display as a horizontal CSS table with two icons per day

=over

=item * param device name

=item * param number of days: optional, default 4 (including today)

=item * param flag:           use minimum of ground and minimum temperature, optional, default 0

=item * return HTML string

=back

=cut

sub AsHtmlH($;$$) {
  my ($d, $days, $useGroundTemperature) = @_;

  $d = "<none>" if(!$d);
  return "$d does not exist or is not a DWD_OpenData module<br>"
        if(!$::defs{$d} || $::defs{$d}{TYPE} ne "DWD_OpenData");

  # create horizontal weather forecast table
  my $items = $days? 2*$days - 1 : 7;
  my $ret = sprintf('<div class="weatherForecast">%s', GetCSS());

  # find two samples of 1st day where at least the 2nd is still in the future
  my @offsets;
  my $now = time();
  my $timeResolution = ::AttrVal($d, 'forecastResolution', 6);
  for (my $index=0; $index<24/$timeResolution; $index++) {
    my $date = ::ReadingsVal($d, "fc0_date", "?");
    my $hourPrefix = "fc0_".$index;
    my $time = ::ReadingsVal($d, $hourPrefix."_time", "");
    my $epoch = ::time_str2num($date.' '.$time);
    if ($timeResolution == 6) {
      # 6 hours steps: default index 1 (06:00 UTC) and 2 (12:00 UTC)
      if ($now < ($epoch + 7200)) {
        # sample not older than 2 hours
        if ($index <= 0) {
          # until 02:00 -> 00:00 + 12:00
          push(@offsets, -1);
          push(@offsets, 0);
        } elsif ($index == 1) {
          # until 08:00 -> 06:00 + 12:00
          push(@offsets, 0);
          push(@offsets, 0);
        } elsif ($index == 2) {
          # until 14:00 -> 12:00 + 18:00
          push(@offsets, 1);
          push(@offsets, 1);
        } else {
          # after 14:00 -> 18:00 + 00:00
          push(@offsets, 2);
          push(@offsets, 2);
        }
        last;
      } elsif ($index > 2) {
        # last sample of day, after 18:00 -> 18:00 + 00:00
        push(@offsets, 2);
        push(@offsets, 2);
      }
    } else {
      # 3 hours steps: default index 2 (06:00 UTC) and 4 (12:00 UTC)
      if ($now < ($epoch + 7200)) {
        # sample not older than 2 hours
        if ($index <= 0) {
          # until 02:00 -> 00:00 + 12:00
          push(@offsets, -2);
          push(@offsets, 0);
        } elsif ($index == 1) {
          # until 05:00 -> 03:00 + 12:00
          push(@offsets, -1);
          push(@offsets, 0);
        } elsif ($index == 2) {
          # until 08:00 -> 06:00 + 12:00
          push(@offsets, 0);
          push(@offsets, 0);
        } elsif ($index == 3) {
          # until 11:00 -> 09:00 + 15:00
          push(@offsets, 1);
          push(@offsets, 1);
        } elsif ($index == 4) {
          # until 14:00 -> 12:00 + 18:00
          push(@offsets, 2);
          push(@offsets, 2);
        } elsif ($index == 5) {
          # until 17:00 -> 15:00 + 21:00
          push(@offsets, 3);
          push(@offsets, 3);
        } elsif ($index == 6) {
          # until 20:00 -> 18:00 + 00:00
          push(@offsets, 4);
          push(@offsets, 4);
        } else {
          # after 20:00 -> 21:00 + 03:00
          push(@offsets, 5);
          push(@offsets, 5);
        }
        last;
      } elsif ($index > 6) {
        # last sample of day, after 21:00 -> 21:00 + 03:00
        push(@offsets, 5);
        push(@offsets, 5);
      }
    }
  }

  # weekday and time
  my $hash = $::defs{$d};
  $ret .= '<div class="weatherHeaderRow">';
  my @dayAndTime;
  my @startTime;
  for (my $i=-1; $i<$items; $i++) {
    my ($day, $index, $dayPrefix, $hourPrefix) = ToForecastIndex($i, \@offsets, $timeResolution);
    my $date = ::ReadingsVal($d, $dayPrefix."_date", "?");
    my $weekday = ::ReadingsVal($d, $dayPrefix."_weekday", "?");
    my $time = ::ReadingsVal($d, $hourPrefix."_time", "");
    $dayAndTime[$i+1] = $weekday.' '.$time;
    if (($i == 0 && $index >= 12/$timeResolution) || ($i > 0 && $i % 2 == 0)) {
      $ret .= sprintf('<div class="weatherWeekday" id="weatherFontBold">%s</div>', $dayAndTime[$i+1]);
    } else {
      $ret .= sprintf('<div class="weatherWeekday">%s</div>', $dayAndTime[$i+1]);
    }

    if ($i == -1) {
      $startTime[$i+1] = $now;
    } else {
      $startTime[$i+1] = DWD_OpenData::ParseDateTimeLocal($hash, ::ReadingsVal($d, $dayPrefix."_date", "1970-01-01") . ' ' . ::ReadingsVal($d, $hourPrefix."_time", "00:00") .':00');
    }
  }
  $ret .= '</div>';

  # prepare alerts
  my $alerts = ::ReadingsVal($d, "a_count", 0);
  my %alertMessages;
  if ($alerts > 0) {
    for (my $i=-1; $i<$items; $i++) {
      my ($day, $index) = ToForecastIndex($i, \@offsets, $timeResolution);
      if ($i >= 0) {
        # future alerts 0=rest of today, 1=tomorrow morning, 2=tomorrow evening, ...
        my $fcStart = $startTime[$i+1];
        my $fcEnd = ($i + 1) < $items? $startTime[$i+2] : ($fcStart + 43200 - 1); # 12 hours
        $alertMessages{"$day-$index"} = undef;
        for(my $a=0; $a<$alerts; $a++) {
          my $start = DWD_OpenData::ParseDateTimeLocal($hash, ::ReadingsVal($d, "a_".$a."_onset", '1970-01-01 00:00:00'));
          my $end   = DWD_OpenData::ParseDateTimeLocal($hash, ::ReadingsVal($d, "a_".$a."_expires", '1970-01-01 00:00:00'));
          if (IsInRange($start, $end, $fcStart, $fcEnd)) {
            if (!defined($alertMessages{"$day-$index"})) {
              $alertMessages{"$day-$index"} = "";
            }
            if (IsActive($start, $end, $fcStart)) {
              # already active, skip onset
              $alertMessages{"$day-$index"} .= sprintf('<div class="weaterAlertMessage" style="color:black; background-color:rgb(%s)">%s bis %s<br>%s<p>%s</div>', ::ReadingsVal($d, "a_".$a."_areaColor", "255, 255, 255"), ::ReadingsVal($d, "a_".$a."_areaDesc", "?"), ::ReadingsVal($d, "a_".$a."_expires", "?"), ::ReadingsVal($d, "a_".$a."_headline", "?"), ::ReadingsVal($d, "a_".$a."_description", "?"));
            } else {
              $alertMessages{"$day-$index"} .= sprintf('<div class="weaterAlertMessage" style="color:black; background-color:rgb(%s)">%s von %s bis %s<br>%s<p>%s</div>', ::ReadingsVal($d, "a_".$a."_areaColor", "255, 255, 255"), ::ReadingsVal($d, "a_".$a."_areaDesc", "?"), ::ReadingsVal($d, "a_".$a."_onset", "?"), ::ReadingsVal($d, "a_".$a."_expires", "?"), ::ReadingsVal($d, "a_".$a."_headline", "?"), ::ReadingsVal($d, "a_".$a."_description", "?"));
            }
          }
        }
      } else {
        # currently valid alerts
        my $fcStart = $startTime[0];
        my $fcEnd = $startTime[1];
        $alertMessages{'NOW'} = undef;
        for(my $a=0; $a<$alerts; $a++) {
          my $start = DWD_OpenData::ParseDateTimeLocal($hash, ::ReadingsVal($d, "a_".$a."_onset", '1970-01-01 00:00:00'));
          my $end   = DWD_OpenData::ParseDateTimeLocal($hash, ::ReadingsVal($d, "a_".$a."_expires", '1970-01-01 00:00:00'));
          if (IsInRange($start, $end, $fcStart, $fcEnd)) {
            if (!defined($alertMessages{'NOW'})) {
              $alertMessages{'NOW'} = "";
            }
            if (IsActive($start, $end, $now)) {
              $alertMessages{'NOW'} .= sprintf('<div class="weaterAlertMessage" style="color:black; background-color:rgb(%s)">%s bis %s<br>%s<p>%s</div>', ::ReadingsVal($d, "a_".$a."_areaColor", "255, 255, 255"), ::ReadingsVal($d, "a_".$a."_areaDesc", "?"), ::ReadingsVal($d, "a_".$a."_expires", "?"), ::ReadingsVal($d, "a_".$a."_headline", "?"), ::ReadingsVal($d, "a_".$a."_description", "?"));
            } else {
              $alertMessages{'NOW'} .= sprintf('<div class="weaterAlertMessage" style="color:black; background-color:rgb(%s)">%s von %s bis %s<br>%s<p>%s</div>', ::ReadingsVal($d, "a_".$a."_areaColor", "255, 255, 255"), ::ReadingsVal($d, "a_".$a."_areaDesc", "?"), ::ReadingsVal($d, "a_".$a."_onset", "?"), ::ReadingsVal($d, "a_".$a."_expires", "?"), ::ReadingsVal($d, "a_".$a."_headline", "?"), ::ReadingsVal($d, "a_".$a."_description", "?"));
            }
          }
        }
      }
    }
  }

  # weather icon
  $ret .= '<div class="weatherDataRow">';
  for(my $i=-1; $i<$items; $i++) {
    my ($day, $index, $dayPrefix, $hourPrefix) = ToForecastIndex($i, \@offsets, $timeResolution);
    my $date = ::ReadingsVal($d, $dayPrefix."_date", "1970-01-01");
    my $time = ::ReadingsVal($d, $hourPrefix."_time", "00:00");
    my $cloudCover = ::ReadingsVal($d, $hourPrefix."_Nf", undef);
    my $epoch = ::time_str2num($date.' '.$time.':00');
    my $imageTag = GetWeatherIconTag(::ReadingsVal($d, $hourPrefix."_ww", undef), $cloudCover, $epoch);
    my $alertKey = $i < 0? 'NOW' : "$day-$index";
    if (defined($alertMessages{$alertKey})) {
      # @TODO vary weatherAlertBoxCenter
      $imageTag .= sprintf('<div class="weatherAlertIcon" title="Wetterwarnungen" tabindex="0"><div class="weatherOverlay"></div> <div class="weatherAlertBoxCenter"><a href="#close" title="Close" class="weatherAlertsClose">x</a><div class="weaterAlertsTitle">Wetterwarnungen %s</div>%s</div></div>', $dayAndTime[$i+1], $alertMessages{$alertKey});
    }
    $ret .= sprintf('<div class="weatherIcon">%s</div>', $imageTag);
  }
  $ret .= '</div>';

  # weather description
  $ret .= '<div class="weatherDataRow">';
  for(my $i=-1; $i<$items; $i++) {
    my ($day, $index, $dayPrefix, $hourPrefix) = ToForecastIndex($i, \@offsets, $timeResolution);
    my $date = ::ReadingsVal($d, $dayPrefix."_date", "1970-01-01");
    my $time = ::ReadingsVal($d, $hourPrefix."_time", "00:00");
    my $epoch = ::time_str2num($date.' '.$time.':00');
    my $code = ::ReadingsVal($d, $hourPrefix."_ww", "-1");
    my $description = "";
    if ($code > 0 && $code != 2) {
      $description = ::ReadingsVal($d, $hourPrefix."_wwd", "?");
    }
    $ret .= sprintf('<div class="weatherCondition">%s</div>', $description);
  }
  $ret .= '</div>';

  # temperature
  $ret .= '<div class="weatherDataRow">';
  for(my $i=-1; $i<$items; $i++) {
    my ($day, $index, $dayPrefix, $hourPrefix) = ToForecastIndex($i, \@offsets, $timeResolution);
    if ($i == -1) {
      # current
      my $tempValue = ::ReadingsVal($d, $hourPrefix."_TT", "?");
      my $tempColor = '';
      if (looks_like_number($tempValue)) {
        if ($tempValue < TEMP_FREEZE) {
          $tempColor = COLOR_FREEZE;
        } elsif ($tempValue > TEMP_WARM) {
          $tempColor = COLOR_WARM;
        }
      }
      $ret .= sprintf('<div class="weatherTemperature" style="color:%s">%s °C</div>', $tempColor, $tempValue);
    } elsif ($i == 0) {
      # 2nd part of current day
      my $tempValueMin = ::ReadingsVal($d, $dayPrefix."_Tn", "?");
      my $tempMinColor = '';
      if (looks_like_number($tempValueMin)) {
        if ($tempValueMin < TEMP_FREEZE) {
          $tempMinColor = COLOR_FREEZE;
        } elsif ($tempValueMin > TEMP_WARM) {
          $tempMinColor = COLOR_WARM;
        }
      }
      my $tempValueMax = ::ReadingsVal($d, $dayPrefix."_Tx", "?");
      my $tempMaxColor = '';
      if (looks_like_number($tempValueMax)) {
        if ($tempValueMax < TEMP_FREEZE) {
          $tempMaxColor = COLOR_FREEZE;
        } elsif ($tempValueMax > TEMP_WARM) {
          $tempMaxColor = COLOR_WARM;
        }
      }
      my $tempValue = ::ReadingsVal($d, $hourPrefix."_TT", "?");
      my $tempColor = '';
      if (looks_like_number($tempValue)) {
        if ($tempValue < TEMP_FREEZE) {
          $tempColor = COLOR_FREEZE;
        } elsif ($tempValue > TEMP_WARM) {
          $tempColor = COLOR_WARM;
        }
      }
      if ($offsets[0] < 0) {
        # before 6:00 UTC: min/max
        $ret .= sprintf('<div class="weatherTemperature" id="weatherFontBold"><span style="color:%s">%s</span>/<span style="color:%s">%s</span> °C</div>', $tempMinColor, $tempValueMin, $tempMaxColor, $tempValueMax);
      } elsif ($offsets[1] < 12/$timeResolution) {
        # before 18:00 UTC: max
        $ret .= sprintf('<div class="weatherTemperature" id="weatherFontBold"><span style="color:%s">max %s °C</span></div>', $tempMaxColor, $tempValueMax);
      } else {
        # after 18:00 UTC: current temp
        $ret .= sprintf('<div class="weatherTemperature" style="color:%s">%s °C</div>', $tempColor, $tempValue);
      }
    } else {
      # 2nd to 7th day
      my ($tempLabel, $tempValue);
      my $firstIcon = $i % 2 == 1;
      if ($firstIcon) {
        $tempLabel = 'min';
        $tempValue = ::ReadingsVal($d, $dayPrefix."_Tn", "?");
        if (defined($useGroundTemperature) && $useGroundTemperature) {
          # use min. ground temperature as alternative to min. air temperature
          my $tempGround = ::ReadingsVal($d, $dayPrefix."_Tg", undef);
          $tempValue = $tempGround if (defined($tempGround) && ($tempValue eq '?' || $tempGround < $tempValue));
        }
      } else {
        $tempLabel = 'max';
        $tempValue = ::ReadingsVal($d, "fc".$day."_Tx", "?");
      }
      my $tempColor = '';
      if (looks_like_number($tempValue)) {
        if ($tempValue < TEMP_FREEZE) {
          $tempColor = COLOR_FREEZE;
        } elsif ($tempValue > TEMP_WARM) {
          $tempColor = COLOR_WARM;
        }
      }
      if ($firstIcon) {
        $ret .= sprintf('<div class="weatherTemperature" style="color:%s">%s %s °C</div>', $tempColor, $tempLabel, $tempValue);
      } else {
        $ret .= sprintf('<div class="weatherTemperature" id="weatherFontBold" style="color:%s">%s %s °C</div>', $tempColor, $tempLabel, $tempValue);
      }
    }
  }
  $ret .= '</div>';

  # max wind speed and direction, precipitation
  $ret .= '<div class="weatherDataRow">';
  for(my $i=-1; $i<$items; $i+=2) {
    my $day = int(($i + 1)/2);
    my ($windSpeed, $windDirection, $windColor, $precipitation, $chanceOfRain);
    for (my $index = 0; $index < 24/$timeResolution; $index++) {
      my $dayPrefix = "fc".$day;
      my $hourPrefix = "fc".$day."_".$index;
      my $date = ::ReadingsVal($d, $dayPrefix."_date", "1970-01-01");
      my $time = ::ReadingsVal($d, $hourPrefix."_time", "00:00");
      my $epoch = ::time_str2num($date.' '.$time.':00');      
      my $value = ::ReadingsVal($d, $hourPrefix."_fx", undef);
      if (defined($value) && (!defined($windSpeed) || $value > $windSpeed) && ($i > 0 || $now < ($epoch + 7200))) {
        # max wind speed of (remaining) day
        $windSpeed = $value;
        $windDirection = ::ReadingsVal($d, $hourPrefix."_dd", "?");
      }
      if ($index == 18/$timeResolution) {
        # precipitation between 06:00 and 18:00
        $precipitation = ::ReadingsVal($d, $hourPrefix."_RR12", "?");
        $chanceOfRain = ::ReadingsVal($d, $hourPrefix."_RRp12", "?");
      }
    }
    if (($i == -1) && ((12/$timeResolution + $offsets[1]) >= 24/$timeResolution)) {
      # when 2nd icon shows 2nd day: use 18:00 to 06:00
      my $hourPrefix = "fc1_".6/$timeResolution;
      $precipitation = ::ReadingsVal($d, $hourPrefix."_RR12", "?");
      $chanceOfRain = ::ReadingsVal($d, $hourPrefix."_RRp12", "?");
    }
    if (defined($windSpeed)) {
      if ($windSpeed < 1) {
        $windSpeed = 'Windstille';
        $windDirection = '';
        $windColor = '';
      } else {
        if ($windSpeed < 6) {
          $windSpeed = 'leiser Zug';
          $windColor = '';
        } elsif ($windSpeed < 12) {
          $windSpeed = 'leichte Brise';
          $windColor = '';
        } elsif ($windSpeed < 20) {
          $windSpeed = 'schwache Brise';
          $windColor = '';
        } elsif ($windSpeed < 29) {
          $windSpeed = 'mäßige Brise';
          $windColor = '';
        } elsif ($windSpeed < 39) {
          $windSpeed = 'frische Brise';
          $windColor = '';
        } elsif ($windSpeed < 50) {
          $windSpeed = 'starker Wind';
          $windColor = 'gold';
        } elsif ($windSpeed < 62) {
          $windSpeed = 'steifer Wind';
          $windColor = 'gold';
        } elsif ($windSpeed < 75) {
          $windSpeed = 'stürmischer Wind';
          $windColor = 'gold';
        } elsif ($windSpeed < 88) {
          $windSpeed = 'Sturm';
          $windColor = 'orange';
        } elsif ($windSpeed < 103) {
          $windSpeed = 'schwerer Sturm';
          $windColor = 'orange';
        } elsif ($windSpeed < 118) {
          $windSpeed = 'orkanartiger Sturm';
          $windColor = 'tomato';
        } else {
          $windSpeed = 'Orkan';
          $windColor = 'tomato';
        }
        if ($windDirection >= 337.5 && $windDirection < 22.5) {
          $windDirection = 'N';
        } elsif ($windDirection < 67.5) {
          $windDirection = 'NO';
        } elsif ($windDirection < 112.5) {
          $windDirection = 'O';
        } elsif ($windDirection < 157.5) {
          $windDirection = 'SO';
        } elsif ($windDirection < 202.5) {
          $windDirection = 'S';
        } elsif ($windDirection < 247.5) {
          $windDirection = 'SW';
        } elsif ($windDirection < 292.5) {
          $windDirection = 'W';
        } else {
          $windDirection = 'NW';
        }
      }
      if (length($windColor) > 0) {
        $ret .= sprintf('<div class="weatherWind" style="color:black; background-color:%s">%s %s</div>', $windColor, $windSpeed, $windDirection);
      } else {
        $ret .= sprintf('<div class="weatherWind">%s %s</div>', $windSpeed, $windDirection);
      }
      my $tempColor = '';
      if ($precipitation > 0 && $chanceOfRain >= PRECIP_RAIN) {
        $tempColor = COLOR_RAIN;
      }
      $ret .= sprintf('<div class="weatherWind" style="color:%s">%s mm %s %%</div>', $tempColor, $precipitation, $chanceOfRain);
    }
  }
  $ret .= '</div>';

  $ret .= '</div>';

  return $ret;
}

# -----------------------------------------------------------------------------

package main;


=head1 FHEM INIT FUNCTION

=head2 DWD_OpenData_Weblink_Initialize($)

FHEM I<Initialize> function

Enables commandref and autoloading of module without changing F<99_myUtils.pm>
if this file is renamed to F<99_DWD_OpenData_Weblink.pm>.

=over

=item * param hash: hash of DWD_OpenData_Weblink device

=back

=cut

sub DWD_OpenData_Weblink_Initialize($) {
  my ($hash) = @_;
}

1;

# -----------------------------------------------------------------------------
#
# CHANGES
#
# 2018-07-04  feature: wind display at 1st icon refined to display max. speed of remaining day
#
# 2018-06-30  feature: temperature display at 2nd icon refined to display min/max/current temperature
#                      depending on current time
#
# 2018-06-23  feature: support forecast with 3 hours resolution
#
# 2018-06-16  coding:  functions converted to package DWD_OpenData_Weblink
#             feature: added function to make the Perl module act like a FHEM module
#                      if module file is renamed to 99_DWD_OpenData_Weblink.pm
#
# 2018-04-02  feature: weather alert indication reimplemented for DWD_OpenData
#
# 2018-03-24  feature: use constants for colors
#             bugfix:  seconds comparison in method IsDay for day/night detection
#
# 2018-03-20  feature: show precipitation of night if 2nd icon shows 2nd day
#
# 2018-03-19  bugfix:  always use black font for wind strength highlighting
#             feature: use constants for temperature and precipitation thresholds
#
# 2018-03-17  feature: set coloured background depending on wind strength
#             feature: set coloured foreground depending on temperature
#             feature: set coloured foreground depending on precipitation
#
# 2018-03-15  feature: modified 2nd icon: replaced min./max day temperature with forecast temperature for 2nd day
#
# 2018-03-03  feature: enhanced 1st day: show temperature of hour of 1st icon instead of min. day temperature
#                                        show min. day temperature together with max. day temperature at 2nd icon
#
# 2018-02-11  feature: precipitation added
#
# 2018-01-27  feature: rewritten for use with DWD_OpenData
#
# 2016-08-26  feature: support multiple alerts at same time and display alert description
#
# 2015-11-04  feature: use CSS styling
#             feature: show alert messages in modal dialog
#
# 2015-11-01  bugfix:  reading c_weather not always available
#             feature: added show alert icon for weather warnings
#
# 2015-10-11  initial release
#
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
#
# @TODO size of condition img not always identical
# @TODO feature: use DWD alert signs
#
# -----------------------------------------------------------------------------

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="DWD_OpenDatautils"></a>
<h3>DWD_Opendata Weblink</h3>
<ul>
    The function <a href="#AsHtmlH($;$$)">DWD_OpenData_Weblink::AsHtmlH</a> returns the HTML code for a horizontally arranged weather forecast with 2 icons per day, one for the morning at 06:00 UTC and one for midday at 12:00 UTC with the exception of the 1st day where the 1st icon approximately corresponds to now and the 2nd icon is 6 hours later. <br><br>

    For each day the minimum and maximum temperatures, the precipitation amount and precipitation probability between 06:00 and 18:00 UTC as well as the highest wind speed of the day and its direction are displayed. If the 2nd icon shows a time after 18:00 UTC the current temperature will be used and if the 2nd icon shows the 2nd day the precipitation relates to the time between 18:00 and 06:00 UTC. <br><br>

    The function requires the name of a DWD_OpenData device as 1st parameter and accepts two optional parameters to limit the number of days to display (1...7, default 4) and to use minimum of ground temperature and minimum air temperature instead of the minimum air temperature (0/1, default 0). <br><br>

    Example: <br><br>

    <code>define MyDWDWeblink weblink htmlCode { DWD_OpenData_Weblink::AsHtmlH("MyDWDDevice") }</code> <br><br>

    where "MyDWDDevice" is the name of your DWD_OpenData device <br><br>

    Notes:
    <ul>
        <li>The properties TT, Tx, Tn, Tg, dd, fx, RR12, RRp12, ww, wwd and Nf must be enabled in your DWD_OpenData device.
        </li>
        <li>This module must be loaded by FHEM before first use. Add <code>eval "use DWD_OpenData_Weblink;";</code>
            e.g. to your <i>99_myUtils.pm</i>. Alternatively you can rename this file to <i>99_DWD_OpenData_Weblink.pm</i>.
        </li>
        <li>The limits for temperature and precipitation colouring can be configured in lines 50 to 52.
        </li>
        <li>The colours for temperature and precipitation colouring can be configured in lines 54 to 56.
            For light background with black font keep defaults, for dark background with white font replace blue with skyblue.
        </li>
        <li>This module is designed for ease of use and does not require additional web resources - but because of this
            it does not comply to best practices in respect to inline images and inline CSS script.
        </li>
        <li>Known issues: day/night detection will only work properly if the forecast station timezone and FHEM timezone are identical.
        </li>
    </ul> <br>
</ul>

=end html
=cut
