# -----------------------------------------------------------------------------
# $Id: 99_RollerShutterController 9 2025-03-24 22:59:00Z jensb $
# -----------------------------------------------------------------------------

=encoding UTF-8

=head1 NAME

RollerShutterController

=head1 LICENSE AND COPYRIGHT


  Copyright (C) 2024 Jens B.

  ALL RIGHTS RESERVED

This script is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This script is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this script; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

A copy of the GNU General Public License, Version 2 can also be found at

http://www.gnu.org/licenses/old-licenses/gpl-2.0.

This copyright notice MUST APPEAR in all copies of the script!

=cut

# -----------------------------------------------------------------------------

package RollerShutterController;

use strict;
use warnings;

use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(gettimeofday);
use Time::Local qw(timelocal);

use feature qw(switch);
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

require Exporter;
our $VERSION = '1.001009';
our @ISA     = qw(Exporter);
our @EXPORT  = qw(ToTime IsTimeBetween);


use constant SCHEDULER_PERIOD => 60; # [s]

use constant {
  TYPE_POSITION     => 'position',
  TYPE_UP_STOP_DOWN => 'up_stop_down',
  TYPE_UP_DOWN => 'up_down',
};

use constant {
  MODE_OFF  => 'off',
  MODE_AUTO => 'auto',
};

use constant {
  STATE_DISABLED   => 'disabled',
  STATE_DEFINED    => 'defined',
  STATE_HOLD       => 'hold',
  STATE_CHANGE     => 'change',
  STATE_STOP       => 'stop',
  STATE_DOWNTIME   => 'downtime',
  STATE_DOOR_BLOCK => 'door block',
  STATE_OFF        => 'off',
};

use constant {
  SHUT_AT_NIGHT_NEVER         => 'never',
  SHUT_AT_NIGHT_WHEN_NOT_HOME => 'whenNotHome',
  SHUT_AT_NIGHT_ALWAYS        => 'always',
};


=head1 FHEM CALLBACK FUNCTIONS


=head2 Define($$)

FHEM I<DefFn>

called when device is defined or FHEM is restarted

=over

=item * param hash: hash of the device

=item * param def: device parameters

=item * return undef on success or error message

=back

=cut

sub Define {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};

  ::Log3 $name, 3, "$name: Define START";

  my @a = split("[ \t][ \t]*", $def);
  my $rollerShutterType = @a == 3 ? $a[2] : TYPE_POSITION;

  return "usage: define <name> RollerShutterController [{" . TYPE_POSITION . "|" . TYPE_UP_DOWN. "|" . TYPE_UP_STOP_DOWN . "}]" if (@a < 2 || @a > 3 || ($rollerShutterType ne TYPE_POSITION && $rollerShutterType ne TYPE_UP_DOWN && $rollerShutterType ne TYPE_UP_STOP_DOWN));

  $hash->{ACTOR_TYPE} = $rollerShutterType;
  $hash->{VERSION} = $VERSION;

  # initially disable notifications
  ::notifyRegexpChanged($hash, undef, 1);

  if (::IsDisabled($name)) {
    ::readingsSingleUpdate($hash, 'state', STATE_DISABLED, 0);
  } else {
    ::InternalTimer(gettimeofday() + 3, 'RollerShutterController::Timer', $hash, 0);
    ::readingsSingleUpdate($hash, 'state', STATE_DEFINED, 0);
  }

  ::Log3 $name, 5, "$name: Define END";

  return undef;
}


=head2 Shutdown($)

FHEM I<ShutdownFn>

called when FHEM is shutdown

=over

=item * param hash: hash of the device

=back

=cut

sub Shutdown {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  ::Log3 $name, 3, "$name: Shutdown START";
  ::RemoveInternalTimer($hash);
  ::Log3 $name, 5, "$name: Shutdown END";

  return undef;
}


=head2 Undef($$)

FHEM I<UndefFn>

called when device is deleted

=over

=item * param hash: hash of the device

=item * param arg: module undefine arguments, will be ignored

=back

=cut

sub Undef {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  ::Log3 $name, 3, "$name: Undef";
  Shutdown($hash);

  return undef;
}


=head2 Attr(@)

FHEM I<AttrFn>

=over

=item * param command: "set" or "del"

=item * param name: name of the device

=item * param attribute: attribute name

=item * param value: attribute value

=item * return C<undef> on success or error message

=back

=cut

sub Attr {
  my ($command, $name, $attribute, $value) = @_;
  my $hash = $::defs{$name};

  for ($command) {
    when ("set") {
      for ($attribute) {
        when ("disable") {
          # enable/disable polling
          if ($::init_done) {
            if ($value) {
              ::RemoveInternalTimer($hash);
              delete($hash->{'.downtimeCanceled'});
              ::readingsSingleUpdate($hash, 'state', STATE_DISABLED, 1);
            } else {
              ::readingsSingleUpdate($hash, 'state', STATE_DEFINED, 1);
              ::InternalTimer(gettimeofday() + 3, 'RollerShutterController::Timer', $hash, 0);
            }
          }
        }

        #when ('mode') {
        #  if ($::init_done) {
        #    if (defined($value) && ($value eq 'off' || $value eq 'auto')) {
        #      Update($hash);
        #    }
        #  }
        #}
      }
    }

    when ("del") {
      for ($attribute) {
        when ("disable") {
          ::readingsSingleUpdate($hash, 'state', STATE_DEFINED, 1);
          ::InternalTimer(gettimeofday() + 3, 'RollerShutterController::Timer', $hash, 0);
        }
      }
    }
  }

  return undef;
}

=head2 Set(@)

FHEM I<AttrFn>

=over

=item * param hash: hash of the device

=item * return C<undef> on success or error message

=back

=cut

sub Set {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  my $command = $a[1];
  my $value = $a[2];

  return "set command missing" if (!defined($command));

  my $result = undef;
  for ($command) {
    when ('position') {
      if (defined($value) && looks_like_number($value) && $value >= 0 && $value <= 100) {
        # manual position change, will trigger downtime
        my $rollerShutterPositionAct = ::ReadingsVal($name, 'positionAct', 0);
        my $rollerShutterPositionSet = $value;
        SetPosition($hash, $rollerShutterPositionAct, $rollerShutterPositionSet);
        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdate($hash, 'positionSet', $rollerShutterPositionSet) if $hash->{READINGS}{'positionSet'}{VAL} != $rollerShutterPositionSet;
        ::readingsBulkUpdate($hash, 'state', STATE_CHANGE);
        ::readingsEndUpdate($hash, 1);
      } else {
        $result = "position value missing or invalid";
      }
    }

    when ('up') {
      ::fhem("set $name position 0");
    }

    when ('down') {
      ::fhem("set $name position 100");
    }

    when ('stop') {
      StopAtPosition($hash, 1);
    }

    when ('cancelDowntime') {
      #$hash->{'.rollerShutterPositionInternallyModified'} = 1;
      #::readingsSingleUpdate($hash, 'downtimeEnd', '', 1);
      $hash->{'.downtimeCanceled'} = 1;
    }

    #when ('mode') {
    #  if (defined($param) && ($param eq 'off' || $param eq 'auto')) {
    #    ::readingsSingleUpdate($hash, 'mode', $param, 1);
    #    Update($hash);
    #  } else {
    #    $result = "parameter value missing or invalid";
    #  }
    #}

    default {
      if ($hash->{ACTOR_TYPE} eq TYPE_POSITION) {
        $result = "unknown set command $command, choose one of position:slider,0,5,100 stop:noArg cancelDowntime:noArg";
      } else {
        $result = "unknown set command $command, choose one of up:noArg down:noArg position:slider,0,5,100 stop:noArg cancelDowntime:noArg";
      }
    }
  }

  return $result;
}


=head2 Get($@)

FHEM I<GetFn>

=over

=item * param hash: hash of the device

=item * param a: array of FHEM command line arguments, min. length 2, a[1] holds get command

=item * return requested data or error message

=back

=cut

sub Get {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  my $result = undef;
  my $command = lc($a[1]);
  for ($command) {
    default {
      $result = "unknown get command $command, choose one of";
    }
  }

  return $result;
}



=head2 Notify($$)

=cut

sub Notify {
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};

  ::Log3 $name, 4, "$name: Notify START";

  return if (::IsDisabled($hash) || !$::init_done);

  my $sourceName = $dev->{NAME};
  my $regex = ::AttrVal($name, 'switchEvents', '');
  my @events = @{::deviceEvents($dev, 0)};
  foreach (@events) {
    my $fqe = "$sourceName:$_";
    if ($fqe =~ m/^$regex$/s) {
      if ($fqe =~ m/:up/s) {
        if (::ReadingsVal($name, 'state', '') ne STATE_CHANGE) {
          ::fhem("set $name up");
        } else {
          ::fhem("set $name stop");
        }
        last;
      } elsif ($fqe =~ m/:down/s) {
        if (::ReadingsVal($name, 'state', '') ne STATE_CHANGE) {
          ::fhem("set $name down");
        } else {
          ::fhem("set $name stop");
        }
        last;
      } elsif ($fqe =~ m/:stop/s) {
        ::fhem("set $name stop");
        last;
      }
    }
  }

  ::Log3 $name, 4, "$name: Notify END";
}


=head2 ToTime($)

=item * param timeString: time hh:mm[:ss]

=item * param date: epoch date, optional

=item * return epoch time based on today or provided date

=cut

sub ToTime {
  my ($timeString, $date) = @_;

  my ($hours, $minutes, $seconds) = split(':', $timeString);

  # seconds are optional
  $seconds = 0 unless defined($seconds);

  # date is optional
  $date = time() unless defined($date);

  my ($second, $minute, $hour, $mday, $month, $year, $wday, $yday, $isdst) = localtime($date);

  return timelocal($seconds, $minutes, $hours, $mday, $month, $year);
}


=head2 IsTimeBetween($$)

=item * param fromHMS: start time hh:mm[:ss]

=item * param toHMS: end time hh:mm[:ss] - when smaller than fromHMS the next day is assumed

=item * param date: epoch date, optional

=item * return 1 if current time is between from and to

=cut

sub IsTimeBetween {
  my ($fromHMS, $toHMS, $date) = @_;

  # date is optional
  $date = time() unless defined($date);

  my $start = ToTime($fromHMS, $date);
  my $end = ToTime($toHMS, $date);

  #::Log 3, "RollerShutterController start:$start date:$date end:$end";

  if ($start <= $end) {
    return $start <= $date && $date <= $end ? 1 : 0;
  } else {
    #::Log 3, "RollerShutterController 1:" . ($start <= $date ? 1 : 0);
    #::Log 3, "RollerShutterController 1:" . ($date <= $end ? 1 : 0);
    return $start <= $date || $date <= $end ? 1 : 0;
  }
}


=head2 SetPosition($$$$)

=cut

sub SetPosition {
  my ($hash, $oldPosition, $newPosition) = @_;
  my $name = $hash->{NAME};

  my $rollerShutterDeviceName = ::AttrVal($name, 'rollerShutterDevice', undef);

  if ($hash->{ACTOR_TYPE} eq TYPE_POSITION) {
    # actor with position control (e.g. EnOcean FSB device)
    if ($newPosition == 0) {
      ::fhem("set $rollerShutterDeviceName opens");
    } elsif ($newPosition == 100) {
      ::fhem("set $rollerShutterDeviceName closes");
    } else {
      ::fhem("set $rollerShutterDeviceName position $newPosition");
    }
  } else {
    # actor with up/down/stop control (3 separate digital output devices)
    my $runtime = ::AttrVal($name, 'shutTime', 30); # [s]
    if (0 < $newPosition && $newPosition < 100) {
      $runtime *= abs($newPosition - $oldPosition)/100;
    }
    if ($newPosition == 0 || $newPosition < $oldPosition) {
      ::fhem("set $rollerShutterDeviceName"."_Zu off");
      ::fhem("set $rollerShutterDeviceName"."_Stop off");
      ::fhem("set $rollerShutterDeviceName"."_Auf on-for-timer 0.5");
      $hash->{'.rollerShutterStarted'} = time();
      ::RemoveInternalTimer($hash);
      ::InternalTimer(gettimeofday() + $runtime, 'RollerShutterController::StopAtPosition', $hash, 0);
      ::Log3 $name, 4, "$name: SetPosition $runtime s up";
    } elsif ($newPosition == 100 || $newPosition > $oldPosition) {
      ::fhem("set $rollerShutterDeviceName"."_Auf off");
      ::fhem("set $rollerShutterDeviceName"."_Stop off");
      ::fhem("set $rollerShutterDeviceName"."_Zu on-for-timer 0.5");
      ::RemoveInternalTimer($hash);
      ::InternalTimer(gettimeofday() + $runtime, 'RollerShutterController::StopAtPosition', $hash, 0);
      $hash->{'.rollerShutterStarted'} = time();
      ::Log3 $name, 4, "$name: SetPosition $runtime s down";
    }
  }
}


=head2 StopAtPosition($)

=cut

sub StopAtPosition {
  my ($hash, $manual) = @_;
  my $name = $hash->{NAME};

  $manual = 0 if (!defined($manual));

  ::Log3 $name, 4, "$name: StopAtPosition START manual:$manual";

  # stop roller shutter
  my $rollerShutterDeviceName = ::AttrVal($name, 'rollerShutterDevice', undef);
  if ($hash->{ACTOR_TYPE} eq TYPE_POSITION) {
    # note: stop command will delete position reading of EnOcean device
    ::fhem("set $rollerShutterDeviceName stop");
    ::readingsSingleUpdate($hash, 'state', STATE_STOP, 1);
  } else {
    ::fhem("set $rollerShutterDeviceName"."_Auf off");
    ::fhem("set $rollerShutterDeviceName"."_Zu off");
    ::fhem("set $rollerShutterDeviceName"."_Stop off");
    my $rollerShutterPositionSet = ::ReadingsVal($name, 'positionSet', 0);
    my $rollerShutterPositionAct = ::ReadingsVal($name, 'positionAct', 0);
    if (!$manual && $rollerShutterPositionSet > 0 && $rollerShutterPositionSet < 100) {
      # automatic stop at position between min and max
      if ($hash->{ACTOR_TYPE} eq TYPE_UP_STOP_DOWN) {
        # stop using stop pulse
        ::fhem("set $rollerShutterDeviceName"."_Stop on-for-timer 1");
      } else {
        # stop by opening a bit
        ::fhem("set $rollerShutterDeviceName"."_Auf on-for-timer 2.2");
        # compensate time
        if ($rollerShutterPositionSet >= $rollerShutterPositionAct) {
          $hash->{'.rollerShutterStarted'} += 2;
        } else {
          $hash->{'.rollerShutterStarted'} -= 2;
        }
      }
    }
    ::RemoveInternalTimer($hash);
    ::InternalTimer(gettimeofday() + SCHEDULER_PERIOD, 'RollerShutterController::Timer', $hash);

    # update actual position
    if ($rollerShutterPositionSet > 0 && $rollerShutterPositionSet < 100) {
      my $change = 100*(time() - $hash->{'.rollerShutterStarted'})/::AttrVal($name, 'shutTime', 30);
      $rollerShutterPositionAct += $rollerShutterPositionSet < $rollerShutterPositionAct ? $change : -$change;
      $rollerShutterPositionAct = 0 if ($rollerShutterPositionAct < 0);
      $rollerShutterPositionAct = 100 if ($rollerShutterPositionAct > 100);
    } else {
      $rollerShutterPositionAct = $rollerShutterPositionSet;
    }

    ::readingsBeginUpdate($hash);
    ::readingsBulkUpdate($hash, 'positionAct', $rollerShutterPositionAct);
    ::readingsBulkUpdate($hash, 'state', STATE_STOP);
    ::readingsEndUpdate($hash, 1);

    ::Log3 $name, 4, "$name: StopAtPosition planned:$rollerShutterPositionSet timed:$rollerShutterPositionAct";
  }

  ::Log3 $name, 4, "$name: StopAtPosition END";
}


=head2 Update($)

periodically monitor sensor to determine roller shutter position

when mode is set to off the position evaluation is still performed but not executed

=over

=item * param args: hash of the device

=back

=cut

sub Update {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $error = undef;

  # date and time
  my $time = time();
  my $isWeekend = ::IsWe(); # weekend or holiday
  my $startOfDay = "00:00:00";
  my $riseTimeEarly = ::AttrVal($name, 'riseTimeEarly', '06:45:00');
  my $riseTimeLate = ::AttrVal($name, 'riseTimeLate', '09:00:00');
  my $eveningTimeEarly = "17:30:00";
  my $eveningTimeLate = "20:30:00";
  my $endOfDay = "23:59:59";
  my $shutAtNight = ::AttrVal($name, 'shutAtNight', SHUT_AT_NIGHT_ALWAYS);

  # actual position and last modified time
  my $rollerShutterPositionAct = undef;
  my $rollerShutterLastModified = undef;
  if ($hash->{ACTOR_TYPE} eq TYPE_POSITION) {
    my $rollerShutterDeviceName = ::AttrVal($name, 'rollerShutterDevice', undef);
    $rollerShutterPositionAct = ::ReadingsVal($rollerShutterDeviceName, 'position', undef);
    $rollerShutterPositionAct = ::ReadingsVal($name, 'positionAct', undef) if (!defined($rollerShutterPositionAct));
    $rollerShutterLastModified = ::time_str2num(::ReadingsTimestamp($rollerShutterDeviceName, 'state', 0)); # [s]

    $error = "attribute rollerShutterDevice not defined" if (!defined($error) && !defined($rollerShutterDeviceName));
  } else {
    $rollerShutterPositionAct = ::ReadingsVal($name, 'positionAct', undef);
    $rollerShutterLastModified = ::time_str2num(::ReadingsTimestamp($name, 'positionAct', 0)); # [s]
  }

  $error = "roller shutter position reading not available" if (!defined($error) && !defined($rollerShutterPositionAct));

  my $rollerShutterPositionSet = ::ReadingsVal($name, 'positionSet', 0);
  my $rollerShutterPositionLast = $hash->{".rollerShutterPositionLast"};
  my $rollerShutterPositionInternallyModified = $hash->{'.rollerShutterPositionInternallyModified'};
  my $rollerShutterPositionExternallyModified = ::ReadingsVal($name, 'externallyModified', 0);
  my $rollerShutterPositionOpen = ::AttrVal($name, 'openPosition', 0);
  my $rollerShutterPositionPartial = ::AttrVal($name, 'partialPosition', 50);
  my $rollerShutterPositionTolerance = ::AttrVal($name, 'positionTolerance', 10);
  my $rollerShutterModificationDowntime = ::AttrVal($name, 'modificationDowntime', 3600); # [s]

  $rollerShutterPositionLast = $rollerShutterPositionAct if (!defined($rollerShutterPositionLast));
  $rollerShutterPositionInternallyModified = 0 if (!defined($rollerShutterPositionInternallyModified));

  # room climate
  my $roomClimateDeviceName = ::AttrVal($name, 'roomClimateDevice', undef);
  my $roomTemperatureAct = ::ReadingsVal($roomClimateDeviceName, 'temperature', undef);
  my $roomTemperaturMin = ::AttrVal($name, 'roomTemperaturMin', 21); # [°C]
  my $roomTemperaturMax = ::AttrVal($name, 'roomTemperaturMax', 23); # [°C]

  $error = "attribute roomClimateDevice not defined" if (!defined($error) && !defined($roomClimateDeviceName));
  $error = "room temperature reading not available" if (!defined($error) && !defined($roomTemperatureAct));

  # outdoor climate
  my $outdoorClimateDeviceName = ::AttrVal($name, 'outdoorClimateDevice', 'Klima_Aussen');
  my $outdoorTemperatureAct = ::ReadingsVal($outdoorClimateDeviceName, 'temperature', undef);
  my $outdoorTemperature24h = ::ReadingsVal($outdoorClimateDeviceName, 'temperature24h', undef);

  $error = "outdoor temperature reading not available" if (!defined($error) && !defined($outdoorTemperatureAct));
  $error = "outdoor temperature24h reading not available" if (!defined($error) && !defined($outdoorTemperature24h));

  # sun intensity
  my $sunDeviceName = ::AttrVal($name, 'sunDevice', 'Sonne');
  my $sunLuminosity = ::ReadingsVal($sunDeviceName, 'luminosity', undef);
  my $sunLuminosityDark = ::AttrVal($name, 'sunLuminosityDark', 20); # [lux]
  my $sunLuminosityTwilight = ::AttrVal($name, 'sunLuminosityTwilight', 0); # [lux]
  my $sunLuminosityLight = ::AttrVal($name, 'sunLuminosityLight', 40); # [lux]
  my $sunInfrared1h = ::ReadingsVal($sunDeviceName, 'ir1h', undef);
  my $isDark = $sunLuminosity <= $sunLuminosityDark;
  my $isLight = $sunLuminosity >= $sunLuminosityLight;

  $error = "sun luminosity reading not available" if (!defined($error) && !defined($sunLuminosity));
  $error = "sun ir1h reading not available" if (!defined($error) && !defined($sunInfrared1h));

  # sun position
  my $astroDeviceName = ::AttrVal($name, 'astroDevice', 'Astro');
  my $sunAzimuth = ::ReadingsVal($astroDeviceName, 'SunAz', undef); # [°]
  my $sunAlitude = ::ReadingsVal($astroDeviceName, 'SunAlt', undef); # [°]
  my $isSunUp = $sunAlitude >= 0 ? 1 : 0; # 0°:REAL -6°:CIVIL
  my $sunRiseTime = ::sunrise_abs("REAL", 0, $eveningTimeEarly, $eveningTimeLate); # [hh:mm:ss]
  my $sunSetTime = ::sunset_abs("REAL", 0, $eveningTimeEarly, $eveningTimeLate); # [hh:mm:ss]
  my $sunRise = ToTime($sunRiseTime, $time);
  my $sunSet = ToTime($sunSetTime, $time);
  my $sunRiseTwilightTime = ::FmtTime($sunRise + 3600); # [hh:mm:ss] one hour after sunrise
  my $sunSetTwilightTime = ::FmtTime($sunSet - 3600); # [hh:mm:ss] one hour before sunset
  my $isEveningTwilightTime = IsTimeBetween($sunSetTwilightTime, $sunSetTime, $time);
  my $isNightTime = IsTimeBetween($sunSetTwilightTime, $riseTimeEarly, $time);
  my $isMorningTwilightTime = IsTimeBetween($sunRiseTime, $sunRiseTwilightTime, $time);    
  my $isEveningTwilight = $isEveningTwilightTime && !$isDark && $sunLuminosity <= $sunLuminosityTwilight;
  my $isNight = $isNightTime && $isDark;
  my $isMorningTwilight = $isMorningTwilightTime && $isLight && $sunLuminosity <= $sunLuminosityTwilight;
  my $isDay = !$isNightTime && $isLight;

  $error = "sun azimuth reading not available" if (!defined($error) && !defined($sunAzimuth));
  $error = "sun altitude reading not available" if (!defined($error) && !defined($sunAlitude));

  # roller shutter orientation
  my $rollerShutterOrientation = ::AttrVal($name, 'orientation', 180); # [°] 0:N 90:E 180:S 270:W

  # presence
  my $presenceDeviceName = ::AttrVal($name, 'presenceDevice', 'Anwesenheit');
  my $presenceAct = ::ReadingsVal($presenceDeviceName, 'presence', undef);

  $error = "presence reading not available" if (!defined($error) && !defined($presenceAct));

  # motion detector
  my $motionDetectorDeviceName = ::AttrVal($name, 'motionDetectorDevice', undef); # 'Bewegung_FE'
  my $motionDetectorLastMotion = 0; # [s]
  if (defined($motionDetectorDeviceName)) {
    $motionDetectorLastMotion = ::ReadingsVal($motionDetectorDeviceName, 'lastMotion', undef);
    $motionDetectorLastMotion = ::time_str2num($motionDetectorLastMotion) if (defined($motionDetectorLastMotion));

    $error = "lastMotion reading not available" if (!defined($error) && !defined($motionDetectorLastMotion));
  }

  # up/down switch
  my $switchEvents = ::AttrVal($name, 'switchEvents', undef);
  if (defined($switchEvents)) {
    # enable notification for device
    my @a = split(':', $switchEvents);
    ::notifyRegexpChanged($hash, $a[0]);
  } else {
    # disable notifications for device
    ::notifyRegexpChanged($hash, undef, 1);
  }

  # room heating or cooling
  my $isRoomCold = $roomTemperatureAct < $roomTemperaturMin ? 1 : 0;
  my $isRoomHot = $roomTemperatureAct > $roomTemperaturMax ? 1 : 0;
  my $isRoomHeatingPreferred = $outdoorTemperature24h < 18 && $isRoomCold ? 1 : 0;
  my $isRoomCoolingPreferred = $isRoomHot ? 1 : 0;
  my $preferredTemperatureChange = $isRoomHeatingPreferred ? 'heating' : $isRoomCoolingPreferred ? 'cooling' : 'none';

  # indoor/outdoor thermal radiation
  # @TODO take partial shading into account
  my $windowPowerFactor = ::AttrVal($name, 'windowPowerFactor', 6); # [W/K]
  my $thermalPower = ($outdoorTemperatureAct - $roomTemperatureAct)*$windowPowerFactor;
  $hash->{thermalPowerFlow} = $thermalPower;

  # sun infrared heating
  # @TODO calculate thermal flow factor based on altitude angle
  # @TODO take sun blocking by surrounding objects into account
  my $thermalFlowFactor = 0;
  my $deltaAzimuth = abs($sunAzimuth - $rollerShutterOrientation);
  if ($deltaAzimuth < 90) {
    $thermalFlowFactor = (90 - $deltaAzimuth)/90;
  }
  my $sunPowerFactor = ::AttrVal($name, 'sunPowerFactor', 5000); # [IR/W]
  my $sunPower = $isSunUp && defined($sunPowerFactor) && $sunPowerFactor > 0 ? $sunInfrared1h*$thermalFlowFactor*$windowPowerFactor/$sunPowerFactor : 0;
  $hash->{sunThermalFlowFactor} = $thermalFlowFactor;
  $hash->{sunPowerFlow} = $sunPower;

  # outdoor thermal flow
  #my $windowPowerHeating = ::AttrVal($name, 'windowPowerHeating', 100);
  #my $windowPowerCooling = ::AttrVal($name, 'windowPowerCooling', -200);
  #my $canOutsideHeatRoom = $windowPower >= $windowPowerHeating;
  #my $canOutsideCoolRoom = $windowPower <= $windowPowerCooling;
  #my $sunInfraredHeating = ::AttrVal($name, 'sunInfraredHeating', 200000);
  #my $canSunHeatRoom = $isSunUp && $sunInfrared1h*$thermalFlowFactor >= $sunInfraredHeating ? 1 : 0;
  my $outsidePowerHeating = ::AttrVal($name, 'outsidePowerHeating', 100);
  my $outsidePowerCooling = ::AttrVal($name, 'outsidePowerCooling', -200);
  my $canOutsideHeatRoom = ($sunPower + $thermalPower) >= $outsidePowerHeating;
  my $canOutsideCoolRoom = ($sunPower + $thermalPower) <= $outsidePowerCooling;

  # door sensors
  my @doorSensorDeviceNames = split(',', ::AttrVal($name, 'doorSensorDevices', ''));
  my $doorsClosed = undef;
  my $doorOpen = undef;
  foreach (@doorSensorDeviceNames) {
    my $doorState = ::ReadingsVal($_, 'state', '');
    if ($doorState =~ /closed.*/) {
      if (!defined($doorOpen)) {
        $doorOpen = 0;
      }
      if (!defined($doorsClosed)) {
        $doorsClosed = 1;
      }
    } elsif ($doorState =~ /open.*/) {
      if (!defined($doorOpen)) {
        $doorOpen = 1;
      } else {
        $doorOpen = $doorOpen || 1;
      }
      if (!defined($doorsClosed)) {
        $doorsClosed = 0;
      } else {
        $doorsClosed = $doorsClosed && 0;
      }
    } else {
      if (!defined($doorOpen)) {
        $doorOpen = 0;
      }
      if (!defined($doorsClosed)) {
        $doorsClosed = 0;
      } else {
        $doorsClosed = $doorsClosed && 0;
      }
    }
  }

  #::Log3 $name, 4, "$name: isWeekend:$isWeekend";

  if (!defined($error)) {
    # external position change detection
    if ($rollerShutterPositionAct != $rollerShutterPositionLast
        && abs($rollerShutterPositionSet - $rollerShutterPositionAct) >= $rollerShutterPositionTolerance
        && !$rollerShutterPositionInternallyModified) {
      $rollerShutterPositionExternallyModified = 1;
    } elsif (::ReadingsAge($name, 'externallyModified', $rollerShutterModificationDowntime) > $rollerShutterModificationDowntime) {
      $rollerShutterPositionExternallyModified = 0;
    }

    # change position?
    $rollerShutterPositionSet = $rollerShutterPositionAct;

    # at night and dark outside
    # or already down and near sunset
    my $newState = STATE_HOLD;
    if ((($shutAtNight eq SHUT_AT_NIGHT_ALWAYS)
      || ($shutAtNight eq SHUT_AT_NIGHT_WHEN_NOT_HOME && $presenceAct ne 'home'))
      && (($isEveningTwilight || $isNight)
          || ((100 - $rollerShutterPositionAct) <= $rollerShutterPositionTolerance
              && ($sunSet - $time) <= $rollerShutterModificationDowntime))) {
      if (!defined($doorsClosed) || $doorsClosed) {
        if ($isEveningTwilight) {
          # partial down
          $rollerShutterPositionSet = $rollerShutterPositionPartial;
          ::Log3 $name, 5, "$name::Update twilight sunLuminosity:$sunLuminosity";
        } else {
          # fully down
          $rollerShutterPositionSet = 100;
          ::Log3 $name, 5, "$name::Update down sunLuminosity:$sunLuminosity";
        }
      } else{
        $newState = STATE_DOOR_BLOCK;
      }
    }

    # when at home and after $riseTimeEarly and movement within last hour
    # or when home and after $riseTimeLate
    # or when not home and after $riseTimeEarly (weekday)
    # or when not home and after $riseTimeLate (weekend/holiday)
    elsif (($shutAtNight eq SHUT_AT_NIGHT_NEVER)
        || ($shutAtNight eq SHUT_AT_NIGHT_WHEN_NOT_HOME && $presenceAct eq 'home')
        || (($shutAtNight eq SHUT_AT_NIGHT_ALWAYS && $presenceAct eq 'home'
            && (($time >= ToTime($riseTimeEarly, $time) && ($time - $motionDetectorLastMotion) < 3600)
             || ($time >= ToTime($riseTimeLate, $time))))
         || ($shutAtNight ne SHUT_AT_NIGHT_NEVER && $presenceAct ne 'home'
             && (($time >= ToTime($riseTimeEarly, $time) && !$isWeekend)
              || ($time >= ToTime($riseTimeLate, $time) && $isWeekend))))) {

      # outside can heat room but cooling preferred
      if (($canOutsideHeatRoom && $isRoomCoolingPreferred)) {
        if (!defined($doorOpen) || !$doorOpen) {
          $rollerShutterPositionSet = $rollerShutterPositionPartial;
        } else{
          $newState = STATE_DOOR_BLOCK;
        }
      }

      # light outside: up
      ## or 1 hour after sunrise
      ## or 1 hour before sunset: partial down
      elsif ((($shutAtNight eq SHUT_AT_NIGHT_NEVER)
           || ($shutAtNight eq SHUT_AT_NIGHT_WHEN_NOT_HOME && $presenceAct eq 'home'))
          || ($isMorningTwilight || $isDay)) {
        if ($isMorningTwilight) {
          # partial up
          $rollerShutterPositionSet = $rollerShutterPositionPartial;
        } else {
          # open
          $rollerShutterPositionSet = $rollerShutterPositionOpen;
        }
      }

      else {
        ::Log3 $name, 5, "$name idle state 1"
      }
    }

    else {
      ::Log3 $name, 5, "$name idle state 0"
    }

    # move to new position?
    my $downtimeEnd = '';
    $hash->{'.rollerShutterPositionInternallyModified'} = 0;
    if (::AttrVal($name, 'mode', MODE_OFF) eq MODE_AUTO) {
      if (abs($rollerShutterPositionSet - $rollerShutterPositionAct) >= $rollerShutterPositionTolerance) {
        # check roller position modification downtime
        my $modificationAge = $time - $rollerShutterLastModified;
        if ($modificationAge > $rollerShutterModificationDowntime || defined($hash->{'.downtimeCanceled'})) {
          # change roller shutter position
          delete($hash->{'.downtimeCanceled'});
          $newState = STATE_CHANGE;
          $hash->{'.rollerShutterPositionInternallyModified'} = 1;
          SetPosition($hash, $rollerShutterPositionAct, $rollerShutterPositionSet);
        } else {
          # wait until position modification downtime has expired
          $newState = STATE_DOWNTIME;
          $downtimeEnd = ::FmtDateTime($rollerShutterLastModified + $rollerShutterModificationDowntime);
        }
      }
    } else {
      $newState = STATE_OFF;
    }

    # update changed readings
    my $oldState = ::ReadingsVal($name, 'state', '');
    ::readingsBeginUpdate($hash);
    ::readingsBulkUpdate($hash, 'downtimeEnd', $downtimeEnd) if $hash->{READINGS}{'downtimeEnd'}{VAL} ne $downtimeEnd;
    ::readingsBulkUpdate($hash, 'preferredTemperatureChange', $preferredTemperatureChange) if $hash->{READINGS}{'preferredTemperatureChange'}{VAL} ne $preferredTemperatureChange;
    ::readingsBulkUpdate($hash, 'positionAct', $rollerShutterPositionAct) if $hash->{READINGS}{'positionAct'}{VAL} != $rollerShutterPositionAct;
    ::readingsBulkUpdate($hash, 'positionSet', $rollerShutterPositionSet) if $hash->{READINGS}{'positionSet'}{VAL} != $rollerShutterPositionSet;
    ::readingsBulkUpdate($hash, 'externallyModified', $rollerShutterPositionExternallyModified) if $hash->{READINGS}{'externallyModified'}{VAL} != $rollerShutterPositionExternallyModified;
    ::readingsBulkUpdate($hash, 'outsideCanHeatRoom', $canOutsideHeatRoom) if $hash->{READINGS}{'outsideCanHeatRoom'}{VAL} != $canOutsideHeatRoom;
    ::readingsBulkUpdate($hash, 'state', $newState) if $hash->{READINGS}{'state'}{VAL} ne $newState;
    ::readingsEndUpdate($hash, $newState ne $oldState ? 1 : 0);

    # prepare next value change detection
    $hash->{'.rollerShutterPositionLast'} = $rollerShutterPositionAct;
  } else {
    # error
    ::readingsSingleUpdate($hash, 'state', "error: $error", 1);
  }
}


=head2 Timer($)

FHEM I<InternalTimer> function

=over

=item * param args: hash of the device

=back

=cut

sub Timer {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  ::Log3 $name, 5, "$name: Timer START";

  my $time = time();
  Update($hash);

  # reschedule timer to next minute
  ::RemoveInternalTimer($hash, 'RollerShutterController::Timer');
  my $nextTime = $time + SCHEDULER_PERIOD;
  ::InternalTimer($nextTime, 'RollerShutterController::Timer', $hash);

  ::Log3 $name, 5, "$name: Timer END";
}


=head1 FHEM MODULE FUNCTIONS

=cut

# -----------------------------------------------------------------------------

package main;


=head1 FHEM INIT FUNCTION

=head2 RollerShutterController_Initialize($)

FHEM I<Initialize> function

called when module is loaded or reloaded

=over

=item * param hash: hash of the device

=back

=cut

sub RollerShutterController_Initialize {
  my ($hash) = @_;

  # FHEM callbacks
  $hash->{DefFn}      = 'RollerShutterController::Define';
  $hash->{ShutdownFn} = 'RollerShutterController::Shutdown';
  $hash->{UndefFn}    = 'RollerShutterController::Undef';
  $hash->{AttrFn}     = 'RollerShutterController::Attr';
  $hash->{SetFn}      = 'RollerShutterController::Set';
  $hash->{NotifyFn}   = 'RollerShutterController::Notify';

  # FHEM attributes
  $hash->{AttrList} = 'disable:0,1 '
                      . 'doorSensorDevices '
                      . 'mode:'.RollerShutterController::MODE_OFF.','.RollerShutterController::MODE_AUTO.' '
                      . 'modificationDowntime '
                      . 'motionDetectorDevice '
                      . 'openPosition '
                      . 'orientation '
                      . 'outsidePowerCooling '
                      . 'outsidePowerHeating '
                      . 'partialPosition '
                      . 'riseTimeEarly '
                      . 'riseTimeLate '
                      . 'rollerShutterDevice '
                      . 'roomClimateDevice '
                      . 'roomTemperaturMin '
                      . 'roomTemperaturMax '
                      . 'shutAtNight:'.RollerShutterController::SHUT_AT_NIGHT_NEVER.','.RollerShutterController::SHUT_AT_NIGHT_WHEN_NOT_HOME.','.RollerShutterController::SHUT_AT_NIGHT_ALWAYS.' '
                      . 'shutTime '
                      . 'switchEvents '
                      . 'sunLuminosityDark '
                      . 'sunLuminosityLight '
                      . 'sunLuminosityTwilight '
                      . 'sunPowerFactor '
                      . 'windowPowerFactor '
                      . $readingFnAttributes;

  ::Log 3, "RollerShutterController module initialized";

  return undef;
}

# -----------------------------------------------------------------------------

1;

# -----------------------------------------------------------------------------

=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary roller shutter controller for EnOcean actor

=item summary_DE Rolladensteuerung für EnOcean Aktor

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="RollerShutterController"></a>
<h3>RollerShutterController</h3>
<ul>
  This module provides automatic control of a roller shutter.<br><br>

  Main features:<br><br>

  <ul>
    <li>support roller shutter actors with a) position, b) up/stop/down and c) up/down control</li>
    <li>time preferences for morning up and evening down</li>
    <li>detect "real" sunrise and sunset via sun luminosity</li>
    <li>partial opening during twilight</li>
    <li>delayed morning opening on weekend and holidays</li>
    <li>immediate morning opening on motion detection</li>
    <li>door sensor support to prevent closing of roller shutter while doors are open</li>
    <li>indoor/outdoor thermal flow estimation (thermal radiation and sun) and thermal shading to prevent heating</li>
  </ul> <br>

  <a name="RollerShutterControllerDefine"></a>
  <b>Define</b><br><br>

  <code>define &lt;name&gt; RollerShutterController [{position|up_stop_down|up_down}]</code> <br><br>
  The optional parameter is the roller shutter actor type and 'position' is the default setting.<br><br><br>

  <a name="RollerShutterControllerSet"/>
  <b>Set</b><br><br>

  <ul>
    <a name="position"/>
    <li>position &lt;percent&gt;<br>
      Move roller shutter to given position;
    </li><br>

    <a name="up"/>
    <li>up<br>
      Move roller shutter up (position 0).
    </li><br>

    <a name="down"/>
    <li>down<br>
      Move roller shutter down (position 100).
    </li><br>

    <a name="stop"/>
    <li>stop<br>
      Stop roller shutter.
    </li><br>

    <a name="cancelDowntime"/>
    <li>stop<br>
      Cancel downtime to allow new setpoint to be applied immediately.
    </li><br>
  </ul> <br>

  <a name="RollerShutterControllerAttr"/>
  <b>Attributes</b><br><br>

  <ul>
    <a name="doorSensorDevices"/>
    <li>doorSensorDevices &lt;device name&gt;, default: none<br>
        Comma seperated list of door sensor devices, optional.
        Roller shutters will not be closed if a door is open.
    </li><br>

    <a name="orientation"/>
    <li>orientation &lt;degree&gt;, default: 180 °<br>
        Compass direction of roller shutter. 0 °: N, 90 °: E, 180 °:S 270 °:W
    </li><br>

    <a name="mode"/>
    <li>mode {off|auto}, default: off<br>
        Set controller mode. When set to "off" the monitoring of the sensors
        will still be performed and the appropriate readings will be updated
        but the roller shutters will not be moved.
    </li>

    <a name="modificationDowntime"/>
    <li>modificationDowntime &lt;seconds&gt;, default: 3600 s<br>
        Consecutive position modification will be blocked until downtime has expired.
        Higher values help to extend the lifetime of actor and motor.
    </li><br>

    <a name="motionDetectorDevice"/>
    <li>motionDetectorDevice &lt;device name&gt;, default: none<br>
        Name of a motion detector device, optional.
        Roller shutters will be opened between after riseTimeEarly when motion was detected.
    </li><br>

    <a name="openPosition"/>
    <li>openPosition &lt;percent&gt;, default: 0 %<br>
        Position to set for open state.
    </li><br>

    <a name="outsidePowerCooling"/>
    <li>outsidePowerCooling &lt;power&gt;, default: -200 W<br>
        Maximum power flow through window from outside to inside where room will start to be cooled.<br>
        Roller shutters could be partially closed, but this is not implemented.
    </li><br>

    <a name="outsidePowerHeating"/>
    <li>windowPowerHeating &lt;power&gt;, default: 100 W<br>
        Minimum power flow through window from outside to inside where room will start to be heated.
        Based on a) the indoor/outdoor thermal radiation through the window glass and b) the sun infrared power (e.g. from a TSL2561 sensor), sun azimuth and roller shutter orientation. Roller shutters will be partially closed.
    </li><br>

    <a name="partialPosition"/>
    <li>partialPosition &lt;percent&gt;, default: 50 %<br>
        Position to set for partial open state (e.g. for thermal shielding).
    </li><br>

    <a name="riseTimeEarly"/>
    <li>riseTimeEarly &lt;HH:MM:SS&gt;, default: 06:45:00<br>
        Roller shutters will not be opened before this time when home.
    </li><br>

    <a name="riseTimeLate"/>
    <li>riseTimeLate &lt;HH:MM:SS&gt;, default: 09:00:00<br>
        Roller shutters will be opened until this time when home.
    </li><br>

    <a name="rollerShutterDevice"/>
    <li>rollerShutterDevice &lt;device name&gt;, default: none<br>
        a) Name of EnOcean roller shutter actor device, must provide a position value in percent.
        b) Prefix of switch devices for up, stop and down.
    </li><br>

    <a name="roomClimateDevice"/>
    <li>roomClimateDevice &lt;device name&gt;, default: none<br>
        Name of temperature sensor device, must provide a temperature value in degrees centigrade.
    </li><br>

    <a name="roomTemperaturMin"/>
    <li>roomTemperaturMin &lt;temperature name&gt;, default: 21 °C<br>
        Minimum comfort room temperature. Shading will be reduced if temperature is lower and outside can provide heating (not implemented).
    </li><br>

    <a name="roomTemperaturMax"/>
    <li>roomTemperaturMax &lt;temperature name&gt;, default: 23 °C<br>
        Maximum comfort room temperature. Roller shutters will be partially closed if outside power flow is the probable cause and the temperature is higher. Set to an impossible high temperature to disable thermal shading.
    </li><br>

    <a name="shutTime"/>
    <li>shutTime &lt;seconds&gt;, default: 30 s<br>
        Time for opening or closing the roller shutter completely to estimate position. Not used for roller shutters with position actor.
    </li><br>

    <a name="shutAtNight"/>
    <li>shutAtNight {never|whenNotHome|always}, default: always<br>
        If shutAtNight is set to "always" or "whenNotHome" the roller shutters will be closed at night. This setting does not affect thermal shading.
    </li><br>

    <a name="switchEvents"/>
    <li>switchEvents &lt;device name&gt;, default: none<br>
        Regular expression for up/down control input device events. Not used for roller shutters with position actor.
    </li><br>

    <a name="sunLuminosityDark"/>
    <li>sunLuminosityDark &lt;lux&gt;, default: 20 lux<br>
        Maximum sun luminosity to be considered as dark / sun down.
    </li><br>

    <a name="sunLuminosityLight"/>
    <li>sunLuminosityLight &lt;lux&gt;, default: 40 lux<br>
        Minimum sun luminosity to be considered as light / sun up, should be higher than <i>sunLuminosityDark</i>.
    </li><br>

    <a name="sunLuminosityTwilight"/>
    <li>sunLuminosityTwilight &lt;lux&gt;, default: 0 lux<br>
        Will move the shutters to <i>partialPosition</i> while brightness is between <i>sunLuminosityLight</i> and <i>sunLuminosityTwilight</i>.
    </li><br>

    <a name="sunPowerFactor"/>
    <li>sunPowerFactor &lt;factor&gt;, default: 5000 IR/W<br>
        Conversion factor from IR sensor value to transmitted power. Set to zero to disable sun power evaluation (e.g. when sun is mostly obstructed outside by large objects).
    </li><br>

    <a name="windowPowerFactor"/>
    <li>windowPowerFactor &lt;factor&gt;, default: 6 W/K<br>
        Product of window heat transmission factor (e.g. 2.8 W/m2*K for double isolated panes) and the window area.
    </li><br>

  </ul>
</ul>

=end html

=begin html_DE

<a name="RollerShutterController"></a>
<h3>RollerShutterController</h3>
<ul>
  Eine detaillierte Modulbeschreibung gibt es auf Englisch - siehe die englische Modulhilfe von <a href="commandref.html#RollerShutterController">DWD_OpenData</a>. <br>
</ul> <br>

=end html_DE

=cut
