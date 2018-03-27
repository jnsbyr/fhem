=pod encoding UTF-8 (äöüÄÖÜ€)
########################################################################################
#
# $Id: 55_DWD_OpenData.pm 4 2018-03-22 20:15:00Z jensb $
#
# FHEM module for DWD Open Data Server
#
########################################################################################
#
#  LICENSE AND COPYRIGHT
#
#  Copyright (C) 2018 jensb
#  Copyright (C) 2018 JoWiemann (use of HttpUtils instead of LWP::Simple)
#
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
########################################################################################
=cut

package main;

use strict;
use warnings;

use Time::Piece;
use Time::HiRes qw(gettimeofday);
use HttpUtils;

use feature qw(switch);
no if $] >= 5.017011, warnings => 'experimental';

my @dwd_dayProperties;
my @dwd_hourProperties;
my @dwd_wwText;


=item DWD_OpenData_Initialize($)

  @param hash hash of DWD_OpenData device

  description
    FHEM module initialization function

=cut

sub DWD_OpenData_Initialize($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{DefFn}   = "DWD_OpenData_Define";
  $hash->{UndefFn} = "DWD_OpenData_Undef";
  $hash->{AttrFn}  = "DWD_OpenData_Attr";
  $hash->{GetFn}   = "DWD_OpenData_Get";

  $hash->{AttrList} = "disable:0,1 forecastStation forecastDays forecastResolution:3,6 forecastWW2Text:0,1 "
                      ."forecastProperties:uzsuSelect,Tx,Tn,Tm,Tg,TT,Td,dd,ff,fx,RR6,RRp6,RR12,RRp12,RR24,RRp24,ev,ww,VV,Nf,NL,NM,NH,SS24,PPPP "
                      ."timezone "
                      .$readingFnAttributes;

  @dwd_dayProperties = ( 'Tx', 'Tn', 'Tg', 'Tm', 'ev', 'SS24' );

  @dwd_hourProperties = ( 'TT', 'Td', 'RR6', 'RRp6', 'RR12', 'RRp12', 'RR24', 'RRp24',
                          'ww', 'Nf', 'NL', 'NM', 'NH', 'dd', 'ff', 'fx', 'VV', 'PPPP' );

  @dwd_wwText = ( "Bewölkungsentwicklung nicht beobachtet",
                  "Bewölkung abnehmend",
                  "Bewölkung unverändert",
                  "Bewölkung zunehmend",
                  # 4 Dunst, Rauch, Staub oder Sand
                  "Sicht durch Rauch oder Asche vermindert",
                  "trockener Dunst (relative Feuchte < 80 %)",
                  "verbreiteter Schwebstaub, nicht vom Wind herangeführt",
                  "Staub oder Sand bzw. Gischt, vom Wind herangeführt",
                  "gut entwickelte Staub- oder Sandwirbel",
                  "Staub- oder Sandsturm im Gesichtskreis, aber nicht an der Station",
                  # 10 Trockenereignisse
                  "feuchter Dunst (relative Feuchte > 80 %)",
                  "Schwaden von Bodennebel",
                  "durchgehender Bodennebel",
                  "Wetterleuchten sichtbar, kein Donner gehört",
                  "Niederschlag im Gesichtskreis, nicht den Boden erreichend",
                  "Niederschlag in der Ferne (> 5 km), aber nicht an der Station",
                  "Niederschlag in der Nähe (< 5 km), aber nicht an der Station",
                  "Gewitter (Donner hörbar), aber kein Niederschlag an der Station",
                  "Markante Böen im Gesichtskreis, aber kein Niederschlag an der Station",
                  "Tromben (trichterförmige Wolkenschläuche) im Gesichtskreis",
                  # 20 Ereignisse der letzten Stunde, aber nicht zur Beobachtungszeit
                  "nach Sprühregen oder Schneegriesel",
                  "nach Regen",
                  "nach Schneefall",
                  "nach Schneeregen oder Eiskörnern",
                  "nach gefrierendem Regen",
                  "nach Regenschauer",
                  "nach Schneeschauer",
                  "nach Graupel- oder Hagelschauer",
                  "nach Nebel",
                  "nach Gewitter",
                  # 30 Staubsturm, Sandsturm, Schneefegen oder -treiben
                  "leichter oder mäßiger Sandsturm, an Intensität abnehmend",
                  "leichter oder mäßiger Sandsturm, unveränderte Intensität",
                  "leichter oder mäßiger Sandsturm, an Intensität zunehmend",
                  "schwerer Sandsturm, an Intensität abnehmend",
                  "schwerer Sandsturm, unveränderte Intensität",
                  "schwerer Sandsturm, an Intensität zunehmend",
                  "leichtes oder mäßiges Schneefegen, unter Augenhöhe",
                  "starkes Schneefegen, unter Augenhöhe",
                  "leichtes oder mäßiges Schneetreiben, über Augenhöhe",
                  "starkes Schneetreiben, über Augenhöhe",
                  # 40 Nebel oder Eisnebel
                  "Nebel in einiger Entfernung",
                  "Nebel in Schwaden oder Bänken",
                  "Nebel, Himmel erkennbar, dünner werdend",
                  "Nebel, Himmel nicht erkennbar, dünner werdend",
                  "Nebel, Himmel erkennbar, unverändert",
                  "Nebel, Himmel nicht erkennbar, unverändert",
                  "Nebel, Himmel erkennbar, dichter werdend",
                  "Nebel, Himmel nicht erkennbar, dichter werdend",
                  "Nebel mit Reifansatz, Himmel erkennbar",
                  "Nebel mit Reifansatz, Himmel nicht erkennbar",
                  # 50 Sprühregen
                  "unterbrochener leichter Sprühregen",
                  "durchgehend leichter Sprühregen",
                  "unterbrochener mäßiger Sprühregen",
                  "durchgehend mäßiger Sprühregen",
                  "unterbrochener starker Sprühregen",
                  "durchgehend starker Sprühregen",
                  "leichter gefrierender Sprühregen",
                  "mäßiger oder starker gefrierender Sprühregen",
                  "leichter Sprühregen mit Regen",
                  "mäßiger oder starker Sprühregen mit Regen",
                  # 60 Regen
                  "unterbrochener leichter Regen oder einzelne Regentropfen",
                  "durchgehend leichter Regen",
                  "unterbrochener mäßiger Regen",
                  "durchgehend mäßiger Regen",
                  "unterbrochener starker Regen",
                  "durchgehend starker Regen",
                  "leichter gefrierender Regen",
                  "mäßiger oder starker gefrierender Regen",
                  "leichter Schneeregen",
                  "mäßiger oder starker Schneeregen",
                  # 70 Schnee
                  "unterbrochener leichter Schneefall oder einzelne Schneeflocken",
                  "durchgehend leichter Schneefall",
                  "unterbrochener mäßiger Schneefall",
                  "durchgehend mäßiger Schneefall",
                  "unterbrochener starker Schneefall",
                  "durchgehend starker Schneefall",
                  "Eisnadeln (Polarschnee)",
                  "Schneegriesel",
                  "Schneekristalle",
                  "Eiskörner (gefrorene Regentropfen)",
                  # 80 Schauer
                  "leichter Regenschauer",
                  "mäßiger oder starker Regenschauer",
                  "äußerst heftiger Regenschauer",
                  "leichter Schneeregenschauer",
                  "mäßiger oder starker Schneeregenschauer",
                  "leichter Schneeschauer",
                  "mäßiger oder starker Schneeschauer",
                  "leichter Graupelschauer",
                  "mäßiger oder starker Graupelschauer",
                  "leichter Hagelschauer",
                  "mäßiger oder starker Hagelschauer",
                  # 90 Gewitter
                  "Gewitter in der letzten Stunde, zurzeit leichter Regen",
                  "Gewitter in der letzten Stunde, zurzeit mäßiger oder starker Regen",
                  "Gewitter in der letzten Stunde, zurzeit leichter Schneefall/Schneeregen/Graupel/Hagel",
                  "Gewitter in der letzten Stunde, zurzeit mäßiger oder starker Schneefall/Schneeregen/Graupel/Hagel",
                  "leichtes oder mäßiges Gewitter mit Regen oder Schnee",
                  "leichtes oder mäßiges Gewitter mit Graupel oder Hagel",
                  "starkes Gewitter mit Regen oder Schnee",
                  "starkes Gewitter mit Sandsturm",
                  "starkes Gewitter mit Graupel oder Hagel");
}

=item DWD_OpenData_Define($$)

  @param  hash hash of DWD_OpenData device
  @param  def  module define parameters, will be ignored

  @return undef on success or error message

  description
    FHEM module DefFn

=cut

sub DWD_OpenData_Define($$) {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};

  # test perl module Text::CSV_XS
  eval {
    require Text::CSV_XS; # 0.40 or higher required
    Text::CSV_XS->new();
  };
  if ($@) {
    my $message = "$name: Perl module Text::CSV_XS not found, see commandref for details how to fix";
    return $message;
  }
  my $textCsvXsVersion = $Text::CSV_XS::VERSION;
  if ($textCsvXsVersion < 0.40) {
    my $message = "$name: Perl module Text::CSV_XS has incompatible version $textCsvXsVersion, see commandref for details how to fix";
    return $message;
  }

  # test TZ environment variable
  $hash->{FHEM_TZ} = $ENV{"TZ"};
  if (!defined($hash->{FHEM_TZ}) || length($hash->{FHEM_TZ}) == 0) {
    my $message = "$name: FHEM TZ environment variable undefined, see commandref for details how to fix";
    return $message;
  }

  # cache timezone attribute
  $hash->{'.TZ'} = AttrVal($hash, 'timezone', $hash->{FHEM_TZ});

  readingsSingleUpdate($hash, 'state', IsDisabled($name)? 'disabled' : 'defined', 1);
  InternalTimer(gettimeofday() + 3, 'DWD_OpenData_Timer', $hash, 0);

  return undef;
}

=item DWD_OpenData_Undef($$)

  @param hash hash of DWD_OpenData device
  @param arg  module undefine arguments, will be ignored

  description
    FHEM module UndefFn ($hash is DWD_OpenData)

=cut

sub DWD_OpenData_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash);

  return undef;
}

=item DWD_OpenData_Attr(@)

  @param  command   "set" or "del"
  @param  name      name of DWD_OpenData device
  @param  attribute attribute name
  @param  value     attribute value

  @return undef on success or error message

  description:
    FHEM module AttrFn

=cut

sub DWD_OpenData_Attr(@) {
  my ($command, $name, $attribute, $value) = @_;
  my $hash = $defs{$name};

  given($command) {
    when("set") {
      given($attribute) {
        when("disable") {
          # enable/disable polling
          if ($main::init_done) {
            if ($value) {
              RemoveInternalTimer($hash);
              readingsSingleUpdate($hash, 'state', 'disabled', 1);
            } else {
              readingsSingleUpdate($hash, 'state', 'defined', 1);
              InternalTimer(gettimeofday() + 3, 'DWD_OpenData_Timer', $hash, 0);
            }
          }
        }
        when("forecastWW2Text") {
          if (!$value) {
            CommandDeleteReading(undef, "$name fc.*wwd");
          }
        }
        when("timezone") {
          if (defined($value) && length($value) > 0) {
            $hash->{'.TZ'} = $value;
          } else {
            return "timezone (e.g. Europe/Berlin) required";
          }
        }
      }
    }

    when("del") {
      given($attribute) {
        when("disable") {
          readingsSingleUpdate($hash, 'state', 'defined', 1);
          InternalTimer(gettimeofday() + 3, 'DWD_OpenData_Timer', $hash, 0);
        }
        when("forecastWW2Text") {
          CommandDeleteReading(undef, "$name fc.*wwd");
        }
        when("timezone") {
          $hash->{'.TZ'} = $hash->{FHEM_TZ};
        }
      }
    }
  }

  return undef;
}

sub DWD_OpenData_GetForecast($$);

=item DWD_OpenData_Get($@)

  @param  hash hash of DWD_OpenData device
  @param  a    array of FHEM command line arguments, min. length 2, a[1] holds get command

  @return requested data or error message

  description:
    FHEM module GetFn

=cut

sub DWD_OpenData_Get($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  my $command = lc($a[1]);

  my $result = undef;
  given($command) {
    when("forecast") {
      my $station = $a[2];
      $station = AttrVal($name, 'forecastStation', undef) if (!defined($station));
      if (defined($station)) {
        $result = DWD_OpenData_GetForecast($hash, $station);
      } else {
        $result = "station code required for $name get $command";
      }
    }

    default {
      $result = "unknown get command $command, choose one of forecast";
    }
  }

  return $result;
}

=item DWD_Timelocal($$)

 @param  hash hash of DWD_OpenData device
         ta   localtime array

 @return epoch seconds

=cut

sub DWD_Timelocal($@) {
  my ($hash, @ta) = @_;
  $ENV{"TZ"} = $hash->{'.TZ'};
  my $t = timelocal(@ta);
  $ENV{"TZ"} = $hash->{FHEM_TZ};
  return $t;
}

=item DWD_Localtime(@)

 @param  hash hash of DWD_OpenData device
 @param  t    epoch seconds

 @return localtime array

=cut

sub DWD_Localtime(@) {
  my ($hash, $t) = @_;
  $ENV{"TZ"} = $hash->{'.TZ'};
  my @ta = localtime($t);
  $ENV{"TZ"} = $hash->{FHEM_TZ};
  return @ta;
}

=item DWD_FormatDateTimeLocal($$)

 @param  hash hash of DWD_OpenData device
 @param  t    epoch seconds

 @return date time string with with format "YYYY-MM-DD HH:MM"

=cut

sub DWD_FormatDateTimeLocal($$) {
  return strftime('%Y-%m-%d %H:%M', DWD_Localtime(@_));
}

=item DWD_FormatDateLocal($$)

 @param  hash hash of DWD_OpenData device
 @param  t    epoch seconds

 @return date string with with format "YYYY-MM-DD"

=cut

sub DWD_FormatDateLocal($$) {
  return strftime('%Y-%m-%d', DWD_Localtime(@_));
}

=item DWD_FormatTimeLocal($$)

 @param  hash hash of DWD_OpenData device
 @param  t    epoch seconds

 @return time string with format "HH:MM"

=cut

sub DWD_FormatTimeLocal($$) {
  return strftime('%H:%M', DWD_Localtime(@_));
}

=item DWD_ParseDateLocal($$)

 @param  hash hash of DWD_OpenData device
         s    date string with format "YYYY-MM-DD"

 @return epoch seconds or undef on error

=cut

sub DWD_ParseDateLocal($$) {
  my ($hash, $s) = @_;
  eval { return DWD_Timelocal($hash, strptime($s, '%Y-%m-%d')) };
  return undef;
}

=item DWD_OpenData_RotateForecast($$;$)

 @param  $hash    hash of DWD_OpenData device
 @param  $station station name, string
 @param  $today   epoch of today 00:00, optional

 @return count of available forcast days

=cut

sub DWD_OpenData_RotateForecast($$;$)
{
  my ($hash, $station, $today) = @_;
  my $name = $hash->{NAME};

  my $daysAvailable = 0;
  while (defined(ReadingsVal($name, 'fc'.$daysAvailable.'_date', undef))) {
    $daysAvailable++;
  }
  #Log3 $name, 5, "$name: A $daysAvailable";

  my $oT = ReadingsVal($name, 'fc0_date', undef);
  my $oldToday = defined($oT)? DWD_ParseDateLocal($hash, $oT) : undef;

  my $stationChanged = ReadingsVal($name, 'fc_station', '') ne $station;
  if ($stationChanged) {
    # different station, delete existing readings
    CommandDeleteReading(undef, "$name fc.*");
    $daysAvailable = 0;
  } elsif (defined($oldToday)) {
    # same station, shift existing readings
    if (!defined($today)) {
      my $time = time();
 	  	my ($tSec, $tMin, $tHour, $tMday, $tMon, $tYear, $tWday, $tYday, $tIsdst) = DWD_Localtime($hash, $time);
      $today = DWD_Timelocal($hash, 0, 0, 0, $tMday, $tMon, $tYear);
    }

    my $daysForward = sprintf("%.0f", $today - $oldToday);  # Perl equivalent for round()
    if ($daysForward > 0) {
      # different day
      if ($daysForward < $daysAvailable) {
        # shift readings forward by days
        my @shiftProperties = ( 'date' );
        foreach my $property (@dwd_dayProperties) {
          push(@shiftProperties, $property);
        }
        for (my $s=0; $s<7; $s++) {
          push(@shiftProperties, $s.'_time');
          push(@shiftProperties, $s.'_wwd');
        }
        foreach my $property (@dwd_hourProperties) {
          for (my $s=0; $s<7; $s++) {
            push(@shiftProperties, $s.'_'.$property);
          }
        }
        for (my $d=0; $d<($daysAvailable - $daysForward); $d++) {
          my $sourcePrefix = 'fc'.($daysForward + $d).'_';
          my $destinationPrefix = 'fc'.$d.'_';
          foreach my $property (@shiftProperties) {
            my $value = ReadingsVal($name, $sourcePrefix.$property, undef);
            if (defined($value)) {
              readingsBulkUpdate($hash, $destinationPrefix.$property, $value);
            } else {
              CommandDeleteReading(undef, $destinationPrefix.$property);
            }
          }
        }
        # delete existing readings of all days that have not been written
        for (my $d=($daysAvailable - $daysForward); $d<$daysAvailable; $d++) {
          CommandDeleteReading(undef, "$name fc".$d."_.*");
        }
        $daysAvailable -= $daysForward;
      } else {
        # nothing to shift, delete existing readings
        CommandDeleteReading(undef, "$name fc.*");
        $daysAvailable = 0;
      }
    }
  }

  return $daysAvailable;
}

sub DWD_OpenData_ProcessForecast($$$);

=item DWD_OpenData_GetForecast($$)

 @param  $hash    hash of DWD_OpenData device
 @param  $station station name, string

=cut

sub DWD_OpenData_GetForecast($$)
{
  my ($hash, $station) = @_;
  my $name = $hash->{NAME};

  if (!IsDisabled($name)) {
    Log3 $name, 5, "$name: DWD_OpenData_GetForecast START";

    # verify timezones
    if (!defined($hash->{FHEM_TZ}) || length($hash->{FHEM_TZ}) == 0) {
      readingsSingleUpdate($hash, 'state', 'error', 1);
      return "$name: FHEM TZ environment variable undefined, see commandref for details how to fix";
    }
    if (!defined($hash->{'.TZ'}) || length($hash->{'.TZ'}) == 0) {
      $hash->{'.TZ'} = $hash->{FHEM_TZ};
    }

    # station name must be 5 chars, extend
    my $fileName = $station;
    while (length($fileName) < 5) {
      $fileName .= '_';
    }
    $fileName .= '-MOSMIX.csv';

    # get forecast for station from DWD server
    readingsSingleUpdate($hash, 'state', 'fetching', 0);
    my $url = 'https://opendata.dwd.de/weather/local_forecasts/poi/' . $fileName;
    my $param = {
                  url        => $url,
                  method     => "GET",
                  timeout    => 5,
                  callback   => \&DWD_OpenData_ProcessForecast,
                  hash       => $hash,
                  station    => $station
                };
    HttpUtils_NonblockingGet($param);

    Log3 $name, 5, "$name: DWD_OpenData_GetForecast END";
  } else {
    return "disabled";
  }
}

=item DWD_OpenData_ProcessForecast($$$)

 @param  param       parameter hash from call to HttpUtils_NonblockingGet
 @param  httpError   nothing or HTTP error string
 @param  fileContent data retrieved from URL

 @return undef on success or error message

=cut

sub DWD_OpenData_ProcessForecast($$$)
{
  my ($param, $httpError, $fileContent) = @_;
  my $hash    = $param->{hash};
  my $name    = $hash->{NAME};
  my $url     = $param->{url};
  my $code    = $param->{code};
  my $station = $param->{station};

  Log3 $name, 5, "$name: DWD_OpenData_ProcessForecast START";

  # preprocess existing readings
  readingsBeginUpdate($hash);
  my $time = time();
  my ($tSec, $tMin, $tHour, $tMday, $tMon, $tYear, $tWday, $tYday, $tIsdst) = DWD_Localtime($hash, $time);
  my $today = DWD_Timelocal($hash, 0, 0, 0, $tMday, $tMon, $tYear);
  my $daysAvailable = DWD_OpenData_RotateForecast($hash, $station, $today);

  my $relativeDay = 0;
  eval {
    if (defined($httpError) && length($httpError) > 0) {
      die "error retrieving URL '$url': $httpError";
    }
    if (defined($code) && $code != 200) {
      die "error $code retrieving URL '$url'";
    }
    if (!defined($fileContent) || length($fileContent) == 0) {
      die "no data retrieved from URL '$url'";
    }

    #Log3 $name, 5, "$name: DWD_OpenData_ProcessForecast: $param->code >$fileContent<";

    # create memory mapped file form received data and parse as CSV
    readingsBulkUpdate($hash, 'state', 'parsing', 0);
    my $csv = Text::CSV_XS->new({ sep_char => ';' });
    if (!defined($csv)) {
      die "error creating CSV parser: ".Text::CSV_XS->error_diag();
    }
    open my $fileHandle, '<', \$fileContent;

    # parse file content
    my @columnNames = @{$csv->getline($fileHandle)};
    if (!@columnNames) {
      die "error parsing header line";
    }
    $csv->column_names (@columnNames);
    my @aoh;
    while (my $row = $csv->getline_hr($fileHandle)) {
      push(@aoh, $row);
    }

    # prepare processing
    readingsBulkUpdate($hash, 'state', 'processing');
    my $forecastWW2Text = AttrVal($name, 'forecastWW2Text', 0);
    my $forecastDays = AttrVal($name, 'forecastDays', 14);
    my $forecastResolution = AttrVal($name, 'forecastResolution', 6);
    my $forecastProperties = AttrVal($name, 'forecastProperties', undef);
    my @properties = split(',', $forecastProperties) if (defined($forecastProperties));
    my @selectedDayProperties;
    my @selectedHourProperties;
    if (!@properties) {
      # no selection: default to all properties
      @selectedDayProperties = @dwd_dayProperties;
      @selectedHourProperties = @dwd_hourProperties;
    } else {
      # split selected properties in day and hour properties
      foreach my $property (@properties) {
        if (grep(/^$property$/, @dwd_dayProperties)) {
          push(@selectedDayProperties, $property);
        } else {
          push(@selectedHourProperties, $property);
        }
      }
    }

    readingsBulkUpdate($hash, "fc_station", $station);
    readingsBulkUpdate($hash, "fc_copyright", "Datenbasis: Deutscher Wetterdienst");

    # process received data: row 0 holds physical units, row 1 holds comment, row 2 hold first data
    my $rowIndex = 0;
    my $reportHour;
    foreach my $row (@aoh)
    {
      if ($rowIndex == 0) {
        # 1st column of row 0 holds the hour and timezone the report was created
        $reportHour = (split(' ', $row->{forecast}, 2))[1];
        $reportHour =~ s/UTC/GMT/g;
      }
      elsif ($rowIndex >= 2) {
        if ($rowIndex == 2) {
          my $reportTime = Time::Piece->strptime($row->{forecast}.' '.$reportHour, '%d.%m.%y %H %Z');
          readingsBulkUpdate($hash, "fc_time", DWD_FormatDateTimeLocal($hash, $reportTime->epoch));
        }
        # analyse date relation between forecast and today
        my $forecastTime = Time::Piece->strptime($row->{forecast}.' '.$row->{parameter}.' GMT', '%d.%m.%y %H:%M %Z');
        my ($fcSec, $fcMin, $fcHour, $fcMday, $fcMon, $fcYear, $fcWday, $fcYday, $fcIsdst) = DWD_Localtime($hash, $forecastTime->epoch);
        my $forecastDate = DWD_Timelocal($hash, 0, 0, 0, $fcMday, $fcMon, $fcYear);
        my $nextRelativeDay = sprintf("%.0f", ($forecastDate - $today)/(24*60*60)); # Perl equivalent for round()
        if ($nextRelativeDay > $forecastDays) {
          # max. number of days processed, done
          last;
        }
        if ($nextRelativeDay < 0) {
          # forecast is older than today, skip
          next;
        }
        $relativeDay = $nextRelativeDay;
        # write data
        my $destinationPrefix = 'fc'.$relativeDay.'_';
        #Log3 $name, 5, "$name: $row->{forecast} $row->{parameter} -> $forecastTime -> $fcMday.$fcMon.$fcYear $fcHour:$fcMin -> $forecastDate -> $destinationPrefix";
        readingsBulkUpdate($hash, $destinationPrefix.'date', DWD_FormatDateLocal($hash, $forecastTime->epoch));
        foreach my $property (@selectedDayProperties) {
          my $value = $row->{$property};
          $value = undef if ($value eq "---");
          if (defined($value)) {
            $value =~ s/,/./g;
            #Log3 $name, 5, "$name: $property = $value";
            readingsBulkUpdate($hash, $destinationPrefix.$property, $value) if (defined($value));
          }
        }
        #Log3 $name, 5, "$name: $rowIndex/$today/$row->{forecast}/$date/$relativeDay/$row->{parameter}/$hour";
        my $hourUTC = (split(':', $row->{parameter}))[0];
        if ($forecastResolution == 3 || ($hourUTC eq "00" || $hourUTC eq "06" || $hourUTC eq "12" || $hourUTC eq "18")) {
          #Log3 $name, 5, "$name: $rowIndex/$today/$row->{forecast}/$relativeDay/$row->{parameter}/$fcHour";
          $destinationPrefix .= int($fcHour/$forecastResolution).'_';
          readingsBulkUpdate($hash, $destinationPrefix.'time', DWD_FormatTimeLocal($hash, $forecastTime->epoch));
          foreach my $property (@selectedHourProperties) {
            my $label = $property;
            $label =~ s/^RRp/RR%/g;
            my $value = $row->{$label};
            $value = undef if (defined($value) && ($value eq "---"));
            if (defined($value)) {
              $value =~ s/,/./g;
              readingsBulkUpdate($hash, $destinationPrefix.$property, $value);
              if ($forecastWW2Text && ($property eq 'ww') && length($value) > 0) {
                readingsBulkUpdate($hash, $destinationPrefix.'wwd', $dwd_wwText[$value]);
              }
            }
          }
        }
      }
      $rowIndex++;
    }
  };

  # abort on exception
  if ($@) {
    my @parts = split(' at ', $@);
    if (@parts) {
      readingsBulkUpdate($hash, 'state', "error: $parts[0]");
    } else {
      readingsBulkUpdate($hash, 'state', "error: $@");
    }
    readingsEndUpdate($hash, 1);
    return @parts? $parts[0] : $@;
  }

  # delete existing readings of all days that have not been written
  #Log3 $name, 5, "$name: B $relativeDay $daysAvailable";
  for (my $d=($relativeDay + 1); $d<$daysAvailable; $d++) {
    CommandDeleteReading(undef, "$name fc".$d."_.*");
  }

  readingsBulkUpdate($hash, 'state', 'initialized');
  readingsEndUpdate($hash, 1);

  Log3 $name, 5, "$name: DWD_OpenData_ProcessForecast END";

  return undef;
}

=item DWD_OpenData_Timer($)

 @param  $hash    hash of DWD_OpenData device

=cut

sub DWD_OpenData_Timer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $time = time();
  my ($tSec, $tMin, $tHour, $tMday, $tMon, $tYear, $tWday, $tYday, $tIsdst) = DWD_Localtime($hash, $time);
  my $tomorrow = DWD_Timelocal($hash, 0, 0, 0, $tMday, $tMon, $tYear) + 86400;

  my $station = AttrVal($name, 'forecastStation', undef);
  if (defined($station)) {
    my $result = DWD_OpenData_GetForecast($hash, $station);
    if (defined($result)) {
      Log3 $name, 4, "$name: error retrieving forecast: $result";
    }
  }

  # schedule next in 1 hour or 3 seconds past midnight
  my $secondsTillMidnight = $tomorrow - $time;
  my $next = $secondsTillMidnight < 3600? $secondsTillMidnight + 3 : 3600;
  InternalTimer(gettimeofday() + $next, 'DWD_OpenData_Timer', $hash, 0);
}

# -----------------------------------------------------------------------------

1;

# -----------------------------------------------------------------------------

=pod

 CHANGES

 22.03.2018 jensb
 bugfix: replaced trunc with round when calculating delta days to cope with summertime

 18.02.2018 jensb
 feature: LWP::Simple replaced by HttpUtils_NonblockingGet (provided by JoWiemann)

=cut

=pod

 @TODO if a property is not available for a given hour to value of the previous or next hour is to be used/interpolated

=cut


=pod
=item device
=item summary DWD Open Data weather forecast
=item summary_DE DWD Open Data Wettervorhersage
=begin html

<a name="DWD_OpenData"></a>
<h3>DWD_OpenData</h3>
<ul>
  The Deutsche Wetterdienst (DWD) provides public weather related data via its <a href="https://www.dwd.de/DE/leistungen/opendata/opendata.html">Open Data Server</a>. Any usage of the service and the data provided by the DWD is subject to the usage conditions on the Open Data Server webpage. An overview of the available content can be found at <a href="https://www.dwd.de/DE/leistungen/opendata/help/inhalt_allgemein/opendata_content_de_en_xls.xls">OpenData_weather_content.xls</a>. <br><br>

  This modules provides a subset of the data called <a href="https://opendata.dwd.de/weather/local_forecasts/poi/">Individual stations of local forecasts of WMO, national and interpolated stations (MOSMIX)</a>. The stations are worldwide POIs and the German DWD network. This data is updated by the DWD typically every 12 hours. <br><br>

  You can request forecasts for different stations in sequence using the command <code>get forecast &lt;station code&gt;</code> or for one station continuously using the attribute <code>forecastStation</code>. To get continuous mode for more than one station you need to create separate DWD_OpenData devices. <br><br>

  In continuous mode the forecast data will be shifted by one day at midnight without requiring new data from the DWD.<br><br>

  Installation notes: <br><br>

  <ul>
      <li>This module requires the additional Perl module <code>Text::CSV_XS (0.40 or higher)</code>. It can be installed depending on your OS and your preferences (e.g. <code>sudo apt-get install libtext-csv-xs-perl</code> or using CPAN). </li><br>

      <li>Data is fetched from the DWD Open Data Server using the FHEM module HttpUtils. If you use a proxy for internet access you need to set the global attribute <code>proxy</code> to a suitable value in the format <code>myProxyHost:myProxyPort</code>. </li><br>

      <li>This module assumes that all timestamps provided by the DWD are UTC where not specified differently. Reading names do not contain absolute days or hours to keep them independent of summertime adjustments. Days are counted relative to "today" of the timezone defined by the attribute of the same name or the timezone specified by the Perl TZ environment variable if undefined. This timezone is also used for date and time readings.  </li><br>

      <li>Like some other Perl modules this module temporarily modifies the TZ environment variable for timezone conversions. This may cause unexpected results in multi threaded environments. Even in single threaded environments this will only work if the FHEM TZ environment variable is defined and set to your timezone. Enter <code>{ $ENV{TZ} }</code> into the FHEM command line to verify. If nothing is displayed or you see an unexpected timezone, fix it by adding <code>export TZ=`cat /etc/timezone`</code> or something similar to your FHEM start script, restart FHEM and check again. After restarting FHEM the Interal <code>FHEM_TZ</code> must show your system timezone. If your FHEM time is wrong after setting the TZ environment variable for the first time (verify with entering <code>{ localtime() }</code> into the FHEM command line) check the system time and timezone of your FHEM server and adjust appropriately. To fix the timezone temporarily without restarting FHEM enter <code>{ $ENV{TZ}='Europe/Berlin' }</code> or something similar into the FHEM command line. See description of attribute <code>timezone</code> how to choose a valid timezone name.  </li>
  </ul><br>

  <a name="DWD_OpenDatadefine"></a>
  <b>Define</b> <br><br>
  <code>define &lt;name&gt; DWD_OpenData</code> <br><br>

  <a name="DWD_OpenDataget"></a>
  <b>Get</b>
  <ul> <br>
      <li>
          <code>get forecast [&lt;station code&gt;]</code><br>
          Fetch forecast for a station. The station code is either a 5 digit WMO station code or an alphanumeric DWD station code from the <a href="https://www.dwd.de/DE/leistungen/met_verfahren_mosmix/mosmix_stationskatalog.pdf">MOSMIX station catalogue</a>. If the attribute <code>forecastDays</code> is set, no <i>station code</i> must be provided.
      </li>
  </ul> <br>

  <a name="DWD_OpenDataattr"></a>
  <b>Attributes</b><br>
  <ul> <br>
      <li>disable {0|1}, default: 0<br>
          Disable fetching data.
      </li><br>
      <li>timezone <tz>, default: Perl TZ environment variable<br>
          <a href="https://en.wikipedia.org/wiki/List_of_tz_database_time_zones">IANA TZ string</a> for date and time readings (e.g. "Europe/Berlin"), can be used to assume the perspective of a station that is in a different timezone or if your Perl TZ environment variable is not set to your local timezone.
      </li><br>
      <li>forecastStation &lt;station code&gt;, default: none<br>
          Setting forecastStation enables automatic updates every 3 hours.
          The station code is either a 5 digit WMO station code or an alphanumeric DWD station code from the <a href="https://www.dwd.de/DE/leistungen/met_verfahren_mosmix/mosmix_stationskatalog.pdf">MOSMIX station catalogue</a>.
      </li><br>
      <li>forecastDays &lt;n&gt;, default: none<br>
          Limits number of forecast days. Setting 0 will still provide forecast data for today.
      </li><br>
      <li>forecastResolution {3|6}, default: 6 h<br>
          Time resolution (number of hours between 2 samples).
      </li><br>
      <li>forecastProperties [&lt;p1&gt;[,&lt;p2&gt;]...] , default: none<br>
          If defined limits the number of properties to the given list. If you remove a property from the list existing readings must be deleted manually in continuous mode. <br>
          Note: Not all selectable properties are available for all stations and for all hours.
      </li><br>
      <li>forecastWW2Text {0|1}, default: 0<br>
          Create additional wwd readings containing the weather code as a descriptive text in German language.
      </li>
  </ul> <br>

  <a name="DWD_OpenDatareadings"></a>
  <b>Readings</b> <br><br>

  The forecast readings are build like this: <br><br>

  <code>fc&lt;day&gt;_[&lt;sample&gt;_]&lt;property&gt;</code> <br><br>

  <ul>
      <li>day - relative day (0 .. 7) based on the timezone attribute where 0 is today</li><br>

      <li>sample - relative time (0 .. 3 or 7) equivalent to multiples of 6 or 3 hours UTC depending on the forecastHours attribute</li><br>

      <li>day properties (see raw data of station for time relation)
          <ul>
             <li>date       - date based on the timezone attribute</li>
             <li>Tn [°C]    - minimum temperature of previous 24 hours (typically until 07:00 station time)</li>
             <li>Tx [°C]    - maximum temperature of previous 24 hours (typically until 19:00 station time)</li>
             <li>Tm [°C]    - average temperature of previous 24 hours</li>
             <li>Tg [°C]    - minimum temperature 5 cm above ground of previous 24 hours</li>
             <li>ev [kg/m2] - evapotranspiration of previous 24 hours</li>
             <li>SS24 [h]   - total sunshine duration of previous 24 hours</li>
          </ul>
      </li><br>

      <li>hour properties
          <ul>
             <li>time       - hour based the timezone attribute</li>
             <li>TT [°C]    - dry bulb temperature at 2 meter above ground</li>
             <li>Td [°C]    - dew point temperature at 2 meter above ground</li>
             <li>dd [°]     - average wind direction 10 m above ground</li>
             <li>ff [km/h]  - average wind speed 10 m above ground</li>
             <li>fx [km/h]  - maximum wind speed in the last hour</li>
             <li>RR6 [mm]   - precipitation amount in the last 6 hours</li>
             <li>RRp6 [%]   - probability of rain in the last 6 hours</li>
             <li>RR12 [mm]  - precipitation amount in the last 12 hours</li>
             <li>RRp12 [%]  - probability of rain in the last 12 hours</li>
             <li>RR24 [mm]  - precipitation amount in the last 24 hours</li>
             <li>RRp24 [%]  - probability of rain in the last 24 hours</li>
             <li>ww         - weather code (see WMO 4680/4677, SYNOP)</li>
             <li>wwd        - German weather code description</li>
             <li>VV [m]     - horizontal visibility</li>
             <li>Nf [1/8]   - effective cloud cover</li>
             <li>NL [1/8]   - lower level cloud cover</li>
             <li>NM [1/8]   - medium level cloud cover</li>
             <li>NH [1/8]   - high level cloud cover</li>
             <li>PPPP [hPa] - pressure equivalent at sea level</li>
          </ul>
      </li>
  </ul> <br>

</ul> <br>

=end html
=cut

