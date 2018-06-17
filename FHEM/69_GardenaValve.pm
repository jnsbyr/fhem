# -----------------------------------------------------------------------------
# $Id: 69_GardenaValve.pm 5 2018-04-21 19:06:00Z jnsbyr $
# -----------------------------------------------------------------------------

=encoding UTF-8

=head1 NAME

GardenaValve - A FHEM Perl module for managing a WiFi controller of a Gardena
1251 irrigation valve.

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

package main;

use strict;
use warnings;

use DateTime;
use JSON;
use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday);
use Time::Local;
use Try::Tiny;

use constant
{
  GARDENA_VALVE_STATE_INITIALIZED   => 'INIT',
  GARDENA_VALVE_STATE_OFF           => 'OFF',
  GARDENA_VALVE_STATE_AUTO          => 'AUTO',
  GARDENA_VALVE_STATE_ON            => 'ON',
  GARDENA_VALVE_STATE_UPDATING      => 'UPDATING',
  GARDENA_VALVE_STATE_LOW_BAT       => 'LOW BAT',
  GARDENA_VALVE_STATE_SHUTDOWN      => 'SHUTDOWN',
  GARDENA_VALVE_STATE_OFFLINE       => 'OFFLINE',
  GARDENA_VALVE_STATE_DISABLED      => 'DISABLED',
};

my %weekdays = (
  'Sun' => 0,
  'Mon' => 1,
  'Tue' => 2,
  'Wed' => 3,
  'Thu' => 4,
  'Fri' => 5,
  'Sat' => 6,
  'all' => 11,
  '2nd' => 12,
  '3rd' => 13,
);

sub GardenaValve_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = 'GardenaValve_Define';
  $hash->{UndefFn}  = 'GardenaValve_Undef';
  $hash->{ParseFn}  = 'GardenaValve_Parse';
  $hash->{SetFn}    = 'GardenaValve_Set';
  $hash->{AttrFn}   = 'GardenaValve_Attr';

  $hash->{AttrList} = 'averageFlow defaultDuration wakeupPeriod '
                    . 'batteryDays batteryOffset '
                    . 'programId schedule:textField-long '
                    . 'timeSync:0,1 timeOffset timeScale '
                    . 'disable:0,1 ' . $readingFnAttributes;
  $hash->{Match}    = '.*';
}

sub GardenaValve_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $ip) = split("[ \t]+", $def);

  if (!defined($ip))
  {
    return "Usage: define <name> GardenaValve <IP address>";
  }

  $hash->{IP} = $ip;
  $hash->{fhem}{modulVersion} = '$Date: 2017-11-26 12:00:00 +0000 (Sun, 26 Nov 2017)$';
  $hash->{STATE} = GARDENA_VALVE_STATE_INITIALIZED;

  $modules{GardenaValve}{defptr}{$ip} = $hash;

  # set default settings on first define
  if ($init_done) {
    $attr{$name}{webCmd} = 'on:off:auto';
    $attr{$name}{devStateIcon} = GARDENA_VALVE_STATE_OFF      .':off '
                               . GARDENA_VALVE_STATE_AUTO     .':off-for-timer '
                               . GARDENA_VALVE_STATE_ON       .':on-till '
                               . GARDENA_VALVE_STATE_UPDATING .':toggle '
                               . GARDENA_VALVE_STATE_LOW_BAT  .':set_on '
                               . GARDENA_VALVE_STATE_SHUTDOWN .':set_off '
                               . GARDENA_VALVE_STATE_DISABLED .': '
                               . '.*:unknown';
    $attr{$name}{icon} = 'sani_water_tap';
  }

  # schedule 1st poll
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday() + 2, 'GardenaValve_Poll', $hash, 0);

  return undef;
}

sub GardenaValve_Parse($$)
{
  my ($chash, $msg) = @_;  # TCP client session hash
  my ($ip, $buffer) = split(':', $msg, 2);

  my $hash = $modules{GardenaValve}{defptr}{$ip}; # GardenaValve hash
  if (defined($hash))
  {
    my $name = $hash->{NAME};

    # abort parsing if disabled
    if (AttrVal($hash->{NAME}, 'disable', 0))
    {
      return "";
    }

    try
    {
      # decode message
      Log3($hash, 5, "$name: received >$buffer<");
      my $json = JSON->new->utf8(0)->decode($buffer);
      if (defined($json->{name}) && ($json->{name} eq 'SleeperRequest' || $json->{name} eq 'SleeperStatus'))
      {
        my $name = $hash->{NAME};

        # update readings
        readingsBeginUpdate($hash);
        if ($json->{name} eq 'SleeperRequest' && $json->{version} ne ReadingsVal($name, "version", ''))
        {
          readingsBulkUpdate($hash, "version", $json->{version});
        }

        # convert time from JSON/UTC to localtime
        my $time = str2time($json->{time});
        my $dt = DateTime->from_epoch(epoch => $time);
        $dt->set_time_zone('Europe/Berlin');
        my $timestamp = $dt->datetime();
        $timestamp =~ s/T/ /;
        if ($json->{name} eq 'SleeperRequest')
        {
          my $offset = $time - time();
          readingsBulkUpdate($hash, "timeOffset", $offset);
          readingsBulkUpdate($hash, "time", $timestamp);
        }

        # mode
        if ($json->{name} eq 'SleeperStatus')
        {
          my $oldMode = ReadingsVal($name, "mode", '?');
          my $manualStart = ReadingsVal($name, 'manualStart', '');
          if ($oldMode ne 'MANUAL' || length($manualStart) > 0)
          {
            if ($json->{mode} ne $oldMode)
            {
              # use remote mode if local mode is not 'MANUAL' or manual start time is defined
              readingsBulkUpdate($hash, "mode", $json->{mode});
            }
          }
          if (($json->{mode} eq 'OFF' || $json->{mode} eq 'AUTO') && length($manualStart) > 0)
          {
            # clear manual start time if remote mode is 'OFF' or 'AUTO'
            readingsBulkUpdate($hash, "manualStart", '');
          }
        }

        # voltage and state
        if ($json->{name} eq 'SleeperStatus')
        {
          # voltage
          my $voltage = $json->{voltage}/1000;
          if ($voltage ne ReadingsVal($name, "voltage", 0))
          {
            readingsBulkUpdate($hash, "voltage", $voltage);
          }

          # state
          my $state = $json->{state};
          my $valve = $state eq GARDENA_VALVE_STATE_ON? 'OPEN' : 'CLOSED';
          if ($json->{mode} eq 'LOW BAT')
          {
            # overwrite valve state when valve operation has been shut down to make it more obvious
            $state = GARDENA_VALVE_STATE_SHUTDOWN;
          }
          elsif ($voltage <= 3.3)
          {
            # overwrite valve state when voltage is low to make it more obvious
            $state = GARDENA_VALVE_STATE_LOW_BAT;
          }
          elsif ($json->{mode} eq 'AUTO' && $valve eq 'CLOSED')
          {
            # overwrite valve state when valve is closed and auto mode is enabled to make it more obvious
            $state = GARDENA_VALVE_STATE_AUTO;
          }
          if ($state ne ReadingsVal($name, "state", ''))
          {
            readingsBulkUpdate($hash, "state", $state);
          }
          if ($valve ne ReadingsVal($name, "valve", ''))
          {
            readingsBulkUpdate($hash, "valve", $valve);
          }
          $hash->{UPDATING} = 0;
        }

        if (defined($json->{totalOpen}))
        {
          # open duration
          my $lastOpenDuration = ReadingsVal($name, "openDuration", 0); # [h]
          my $openDuration = $json->{totalOpen} / 3600.0; # [s] -> [h]
          if ($openDuration ne $lastOpenDuration)
          {
            readingsBulkUpdate($hash, "openDuration", $openDuration);

            # open overall
            my $deltaDuration = 0.0; # [h]
            if (abs($openDuration - $lastOpenDuration) > 0.0003)
            {
              Log3($hash, 3, "$name: $json->{name} changed open duration $lastOpenDuration -> $openDuration");

              # overall duration
              if ($lastOpenDuration <= 0)
              {
                # last open duration is (less than) zero (FHEM reading invalid or reset), assume zero change
                $deltaDuration = 0.0;
              }
              elsif ($openDuration >= $lastOpenDuration)
              {
                # open duration is unchanged or higher than last time, get delta
                $deltaDuration = $openDuration - $lastOpenDuration;
              }
              else
              {
                # last open duration is higher than current duration (valve controller reset), use absolute
                $deltaDuration = $openDuration;
              }
            }
            readingsBulkUpdate($hash, "openDurationOverall", ReadingsVal($name, "openDurationOverall", 0) + $deltaDuration);

            # overall volume
            my $averageFlow = AttrVal($name, 'averageFlow', 0); # [l/min]
            if ($averageFlow > 0)
            {
              my $lastVolume = ReadingsVal($name, "volumeOverall", 0); # [m3]
              my $volume = $lastVolume + 60.0*$deltaDuration*$averageFlow/1000.0;
              readingsBulkUpdate($hash, "volumeOverall", $volume);
              if ($lastVolume == 0 && $volume > 0)
              {
                readingsBulkUpdate($hash, "volumeInitialized", TimeNow());
              }
            }
          }
        }

        if (defined($json->{opened}))
        {
          # open count
          my $lastOpenCount = ReadingsVal($name, "openCount", 0);
          my $openCount = $json->{opened};
          if ($openCount ne $lastOpenCount)
          {
            readingsBulkUpdate($hash, "openCount", $openCount);

            # open overall
            my $deltaCount = 0;
            if (abs($openCount - $lastOpenCount) > 0)
            {
              # overall count
              if ($lastOpenCount <= 0)
              {
                # last open count is (less than) zero (FHEM reading invalid or reset), assume change by one
                $deltaCount = 1;
              }
              elsif ($openCount >= $lastOpenCount)
              {
                # open count is unchanged or higher than last time, get delta
                $deltaCount = $openCount - $lastOpenCount;
              }
              else
              {
                # last open count is higher than current count (valve controller reset), use absolute
                $deltaCount = $openCount;
              }
            }
            readingsBulkUpdate($hash, "openCountOverall", ReadingsVal($name, "openCountOverall", 0) + $deltaCount);
          }
        }

#        wakeup
#        if (ReadingsVal($name, "wakeupPeriod", 0) ne $json->{wakeup})
#        {
#          readingsBulkUpdate($hash, "wakeupPeriod", $json->{wakeup});
#        }

        # RSSI
        if (defined($json->{RSSI}) && $json->{RSSI} ne ReadingsVal($name, "RSSI", 0))
        {
          readingsBulkUpdate($hash, "RSSI", $json->{RSSI});
        }

        readingsEndUpdate($hash, 1);

        if ($json->{name} eq 'SleeperRequest')
        {
          # command preparation
          my ($now, $microseconds) = gettimeofday();
          my $manualStart = ReadingsVal($name, 'manualStart', '');
          my $manualStartTime = length($manualStart)? time_str2num($manualStart) : 0;
          my $defaultDuration = AttrVal($name, 'defaultDuration', 0);   # seconds
          my $mode = ReadingsVal($name, 'mode', 'OFF');
          if ($mode eq 'MANUAL' && $manualStartTime == 0)
          {
            # manual start time undefined
            $mode = 'OFF';
          }

          # send command
          my $timeSync = AttrVal($name, 'timeSync', 1);
          my $timestamp = strftime("%Y-%m-%dT%H:%M:%S", gmtime($now));
          my $milliseconds = sprintf('%03dZ', $microseconds/1000);
          my $start = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($manualStartTime));
          my $reply = "{\"name\":\"SleeperCommand\", \"time\":\"$timestamp.$milliseconds\", \"setTime\":$timeSync, \"mode\":\"$mode\", \"start\":\"$start\", \"duration\":$defaultDuration";
          my $wakeupPeriod = AttrVal($name, 'wakeupPeriod', 0);   # seconds
          if ($wakeupPeriod > 0)
          {
            $reply .= ", \"wakeup\":$wakeupPeriod";
          }
          my $timeScale = AttrVal($name, 'timeScale', -1);
          if ($timeScale > -1)
          {
            $timeScale = int(100.0*$timeScale + 0.5); # percent change -> scaled by 100
            $reply .= ", \"timeScale\":$timeScale";
          }
          my $timeOffset = AttrVal($name, 'timeOffset', -999);
          if ($timeOffset > -999)
          {
            $reply .= ", \"timeOffset\":$timeOffset";
          }
          my $batteryOffset = AttrVal($name, 'batteryOffset', -999);
          if ($batteryOffset > -999)
          {
            $reply .= ", \"voltageOffset\":$batteryOffset";
          }
          my $programId = AttrVal($name, 'programId', 0);
          if ($json->{programId} != $programId)
          {
            # program id has changed, send new activity program
            my @schedule = eval(AttrVal($name, 'schedule', 0));
            my $activities = @schedule;
            if ($activities > 0 && $activities % 3 == 0)
            {
              my @t = localtime(time);
              my $gmtOffset = (timegm(@t) - timelocal(@t))/60; # minutes

              $reply .= ", \"programId\":$programId";
              $reply .= ", \"activities\":[";
              for (my $activity = 0; $activity < $activities/3; $activity++)
              {
                my $weekday   = $schedule[3*$activity+0];
                my $duration  = $schedule[3*$activity+2];

                # convert activity timestamp to GMT timestamp
                my $timestamp = $schedule[3*$activity+1];
                my @timeParts = split(':', $timestamp);
                my $minuteOfDay = 60*$timeParts[0] + $timeParts[1] - $gmtOffset;
                if ($weekday eq 'all' || $weekday eq '2nd' || $weekday eq '3rd')
                {
                  # every 1st, 2nd or 3rd day, keep day unchanged
                  if ($minuteOfDay < 0)
                  {
                    # previous day
                    $minuteOfDay += 1440;
                  }
                  elsif ($minuteOfDay >= 1440)
                  {
                    # next day
                    $minuteOfDay -= 1440;
                  }
                }
                else
                {
                  # specific day, shift day if crossing midnight
                  $weekday = $weekdays{$weekday};
                  if ($minuteOfDay < 0)
                  {
                    # previous day
                    $minuteOfDay += 1440;
                    $weekday = ($weekday + 6)%7;
                  }
                  elsif ($minuteOfDay >= 1440)
                  {
                    # next day
                    $minuteOfDay -= 1440;
                    $weekday = ($weekday + 1)%7;
                  }
                }
                $timestamp = sprintf("%02d:%02d", $minuteOfDay/60, $minuteOfDay%60);

                if (looks_like_number($weekday))
                {
                  $reply .= "{\"day\":$weekday, \"start\":\"$timestamp\", \"duration\":$duration}";
                }
                else
                {
                  $reply .= "{\"day\":\"$weekday\", \"start\":\"$timestamp\", \"duration\":$duration}";
                }
              }
              $reply .= "]";
            }
            $reply .= '}';
          }
          Log3($hash, 5, "$name: sending >$reply<");
          syswrite($chash->{CD}, $reply);
        }
      }
    }
    catch
    {
      Log3($hash, 3, "$name: $_ >$buffer<");
    };

    $hash->{'.noDispatchVars'} = 1;

    return $name;
  }
  else
  {
    return "UNDEFINED GardenaValve_$ip GardenaValve $ip";
  }
}

sub GardenaValve_Set($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  return "argument required" if (!defined($a[1]));

  my $usage = "unsupported argument " . $a[1] . ", choose one of off:noArg manual:noArg auto:noArg on:noArg on-till:textField";

  if (lc($a[1]) eq "on")
  {
    if (!AttrVal($hash->{NAME}, 'disable', 0))
    {
      my $manualStart = strftime("%Y-%m-%d %H:%M:%S", localtime(time_str2num(ReadingsTimestamp($name, 'time', TimeNow())) + AttrVal($name, 'wakeupPeriod', 0)));

      readingsBeginUpdate($hash);
      $hash->{UPDATING} = 1;
      readingsBulkUpdate($hash, 'manualStart', $manualStart);
      readingsBulkUpdate($hash, 'mode', 'MANUAL');
      readingsBulkUpdate($hash, 'state', GARDENA_VALVE_STATE_UPDATING, 1);
      readingsEndUpdate($hash, 1);
    }
    return undef;
  }
  elsif (lc($a[1]) eq "on-till")
  {
    if (!AttrVal($hash->{NAME}, 'disable', 0))
    {
      my $manualStart;
      if (scalar(@a) == 4)
      {
        my $epoch = time_str2num("$a[2] $a[3]");
        if (!$epoch)
        {
          return "start time argument must be a valid timestamp (YYYY-MM-DD HH:MM:SS)";
        }
        $manualStart = "$a[2] $a[3]";
      }
      else
      {
        return "date and/or time argument missing or invalid";
      }

      readingsBeginUpdate($hash);
      $hash->{UPDATING} = 1;
      readingsBulkUpdate($hash, 'manualStart', $manualStart);
      readingsBulkUpdate($hash, 'mode', 'MANUAL');
      readingsBulkUpdate($hash, 'state', GARDENA_VALVE_STATE_UPDATING, 1);
      readingsEndUpdate($hash, 1);
    }
    return undef;
  }
  elsif (lc($a[1]) eq "off")
  {
    if (!AttrVal($hash->{NAME}, 'disable', 0))
    {
      if (ReadingsVal($name, "mode", "") ne 'OFF')
      {
        $hash->{UPDATING} = 1;
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, 'manualStart', '');
        readingsBulkUpdate($hash, 'mode', 'OFF');
        readingsBulkUpdate($hash, 'state', GARDENA_VALVE_STATE_UPDATING, 1);
        readingsEndUpdate($hash, 1);
      }
    }
    return undef;
  }
  elsif (lc($a[1]) eq "manual")
  {
    if (!AttrVal($hash->{NAME}, 'disable', 0))
    {
      $hash->{UPDATING} = 1;
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, 'manualStart', '');
      readingsBulkUpdate($hash, 'mode', 'MANUAL');
      readingsBulkUpdate($hash, 'state', GARDENA_VALVE_STATE_UPDATING, 1);
      readingsEndUpdate($hash, 1);
    }
    return undef;
  }
  elsif (lc($a[1]) eq "auto")
  {
    if (!AttrVal($hash->{NAME}, 'disable', 0))
    {
      if (ReadingsVal($name, "mode", "") ne 'AUTO')
      {
        $hash->{UPDATING} = 1;
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, 'manualStart', '');
        readingsBulkUpdate($hash, 'mode', 'AUTO');
        readingsBulkUpdate($hash, 'state', GARDENA_VALVE_STATE_UPDATING, 1);
        readingsEndUpdate($hash, 1);
      }
    }
    return undef;
  }
  else
  {
    return $usage;
  }
}

sub GardenaValve_Undef($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  return undef;
}

sub GardenaValve_Attr(@)
{
  my ($cmd,$name,$attrName,$attrValue) = @_;
  my $hash = $defs{$name};

  my $msg = '';
  if ($cmd eq "set")
  {
    if ($attrName eq "defaultDuration")
    {
      my $valid = defined($attrValue) && looks_like_number($attrValue) && $attrValue >= 5 && $attrValue <= 7200;
      if (!$valid)
      {
        $msg = "attribute $attrName must be a number between 5 and 7200 (seconds)";
      }
      else
      {
        my $now = time();
        my $manualStart = time_str2num(ReadingsVal($name, 'manualStart', ''));
        if ($manualStart + $attrValue > $now)
        {
          $hash->{UPDATING} = 1;
        }
      }
    }
    elsif ($attrName eq "programId")
    {
      my $valid = defined($attrValue) && looks_like_number($attrValue) && $attrValue >= 1 && $attrValue <= 2147483647;
      if (!$valid)
      {
        $msg = "attribute $attrName must be a number between 1 and 2147483647";
      }
    }
    elsif ($attrName eq "schedule")
    {
      my @schedule = eval($attrValue);
      my $count = @schedule;
      if ($count % 3 != 0)
      {
        $msg = "attribute $attrName must be an array of 1 to 32 activities\n" . "each activity must be an array of the 3 elements weekday, time and duration\n" . "example: ( ('all', '06:20', 60), ('Sun', '20:35', 600) )\n";
      }
      elsif ($count > 96)
      {
        $msg = "attribute $attrName maximum number or 32 activities exceeded";
      }
      my $index = 0;
      foreach my $element (@schedule)
      {
        if ($index % 3 == 0)
        {
          if (!exists($weekdays{$element}))
          {
            $msg = "attribute $attrName must be an array of 1 to 32 activities\n" . "example: ( ('all', '06:20', 60), ('Sun', '20:35', 600) )\n" . "invalid weekday '$element', valid values are Mon, Tue, Wed, Thu, Fri, Sat, Sun, all (for every day), 2nd (for every 2nd day of year) and 3rd (for every 3rd day of year)";
            last;
          }
        }
        elsif ($index % 3 == 1)
        {
          my @timeParts = split(':', $element);
          if ($#timeParts != 1 || length($timeParts[0]) != 2 || length($timeParts[1]) != 2)
          {
            $msg = "attribute $attrName must be an array of 1 to 32 activities\n" . "example: ( ('all', '06:20', 60), ('Sun', '20:35', 600) )\n" . "invalid time '$element', must have format hh:mm";
          }
          elsif ($timeParts[0] < 0 || $timeParts[0] > 23)
          {
            $msg = "attribute $attrName must be an array of 1 to 32 activities\n" . "example: ( ('all', '06:20', 60), ('Sun', '20:35', 600) )\n" . "invalid hour in '$element', must be a number between 0 and 23";
          }
          elsif ($timeParts[1] < 0 || $timeParts[1] > 59)
          {
            $msg = "attribute $attrName must be an array of 1 to 32 activities\n" . "example: ( ('all', '06:20', 60), ('Sun', '20:35', 600) )\n" . "minute in '$element', must be a number between 0 and 59";
          }
        }
        elsif ($index % 3 == 2)
        {
          my $valid = defined($element) && looks_like_number($element) && ($element == 0 || $element >= 5 && $element <= 7200);
          if (!$valid)
          {
            $msg = "attribute $attrName must be an array of 1 to 32 activities\n" . "example: ( ('all', '06:20', 60), ('Sun', '20:35', 600) )\n" . "invalid duration '$element', must be 0 or a number between 5 and 7200 (seconds)";
            last;
          }
        }
        $index++;
      }
      if (length($msg) == 0)
      {
        # schedule is valid, create unique activity program id
        $msg = CommandAttr(undef, $name . ' programId ' . time() % 2147483647);
        if (length($msg) == 0)
        {
          $hash->{UPDATING} = 1;
        }
      }
    }
    elsif ($attrName eq "timeSync")
    {
      my $valid = defined($attrValue) && looks_like_number($attrValue) && $attrValue >= 0 && $attrValue <= 1;
      if (!$valid)
      {
        $msg = "attribute $attrName must be a number between 0 and 1";
      }
      else
      {
        $hash->{UPDATING} = 1;
      }
    }
    elsif ($attrName eq "timeScale")
    {
      my $valid = defined($attrValue) && looks_like_number($attrValue) && $attrValue >= 0.0 && $attrValue <= 10.0;
      if (!$valid)
      {
        $msg = "attribute $attrName must be a number between -10.00 and 10.00 (percent)";
      }
      else
      {
        $hash->{UPDATING} = 1;
      }
    }
    elsif ($attrName eq "timeOffset")
    {
      my $valid = defined($attrValue) && looks_like_number($attrValue) && $attrValue >= -500 && $attrValue <= +500;
      if (!$valid)
      {
        $msg = "attribute $attrName must be a number between -500 and +500 (milliseconds)";
      }
      else
      {
        $hash->{UPDATING} = 1;
      }
    }
    elsif ($attrName eq "averageFlow")
    {
      my $valid = defined($attrValue) && looks_like_number($attrValue) && $attrValue >= 0 && $attrValue <= +100;
      if (!$valid)
      {
        $msg = "attribute $attrName must be a number between 0 and 100 (liter/minute)";
      }
    }
    elsif ($attrName eq "batteryOffset")
    {
      my $valid = defined($attrValue) && looks_like_number($attrValue) && $attrValue >= -500 && $attrValue <= 500;
      if (!$valid)
      {
        $msg = "attribute $attrName must be a number between -500 and 0 (millivolt)";
      }
      else
      {
        my $voltage = ReadingsVal($name, "voltage", 0);
        my $oldOffset = AttrVal($name, 'batteryOffset', 1000);
        if ($voltage > 0 && $oldOffset < 1000)
        {
          # immediately recalculate voltage based on new offset
          readingsSingleUpdate($hash, "voltage", $voltage - $oldOffset/1000 + $attrValue/1000, 0);
        }
        $hash->{UPDATING} = 1;
      }
    }
    elsif ($attrName eq "wakeupPeriod")
    {
      my $valid = defined($attrValue) && looks_like_number($attrValue) && $attrValue >= 5 && $attrValue <= 3600;
      if (!$valid)
      {
        $msg = "attribute $attrName must be a number between 1 and 3600 (seconds)";
      }
      else
      {
        # rough standby battery life estimate in days assuming 40 uA deep sleep current and 100 mA activity current for 1700 ms with a battery capacity of 2.6 Ah (slightly pessimistic)
        # additional load of activities is not accounted for
        my $wakeupsPerDay = 86400 / ($attrValue + 1.7);
        my $ampereHoursPerDay = ($attrValue*$wakeupsPerDay *0.00004 + 1.7*$wakeupsPerDay*0.1)/3600;
        $msg = CommandAttr(undef, $name . ' batteryDays ' . int(2.6/$ampereHoursPerDay + 0.5));
        $hash->{UPDATING} = 1;
      }
    }
    elsif ($attrName eq 'disable')
    {
      my $disable = (defined($attrValue) && looks_like_number($attrValue) && $attrValue >= 0 && $attrValue <= 1) ? $attrValue : -1;
      if ($disable > 0) {
        # stop timer
        RemoveInternalTimer($hash);
        readingsSingleUpdate($hash, 'state', GARDENA_VALVE_STATE_DISABLED, 1);
      } elsif ($disable == 0) {
        # restart timer
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 2, 'GardenaValve_Poll', $hash, 0);
        readingsSingleUpdate($hash, 'state', GARDENA_VALVE_STATE_INITIALIZED, 1);
      } elsif ($disable < 0) {
        $msg = 'invalid disable value, must be 0 or 1';
      }
    }
  }
  elsif ($cmd eq 'del')
  {
    if ($attrName eq 'disable')
    {
      # restart timer
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday() + 2, 'GardenaValve_Poll', $hash, 0);
      readingsSingleUpdate($hash, 'state', GARDENA_VALVE_STATE_INITIALIZED, 1);
    }
    elsif ($attrName eq 'wakeupPeriod')
    {
      CommandDeleteAttr(undef, $name . ' batteryDays ');
    }
  }

  return ($msg) ? $msg : undef;
}

sub GardenaValve_Poll($)
{
  my ($hash) =  @_;
  my $name = $hash->{NAME};

  my $state = ReadingsVal($name, 'state', '');
  if (!AttrVal($hash->{NAME}, "disable", 0))
  {
    # check last update
    my $now = time();
    my $lastUpdateText = ReadingsTimestamp($name, 'time', '');
    my $lastUpdate = time_str2num($lastUpdateText);
    my $wakeupPeriod = AttrVal($name, 'wakeupPeriod', 30);  ; # seconds
    if ((length($lastUpdateText) == 0 || ($lastUpdate > 0 && ($now - $lastUpdate) > 2*$wakeupPeriod)) && $state ne GARDENA_VALVE_STATE_OFFLINE)
    {
      # device has never reported or not reported for more than 2 periods
      readingsSingleUpdate($hash, 'state', GARDENA_VALVE_STATE_OFFLINE, 1);
    }

    # schedule next polling
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + $wakeupPeriod, 'GardenaValve_Poll', $hash, 0);
  }
  else
  {
    # device is disabled
    if ($state ne GARDENA_VALVE_STATE_DISABLED)
    {
      # stop timer
      RemoveInternalTimer($hash);
      readingsSingleUpdate($hash, 'state', GARDENA_VALVE_STATE_DISABLED, 1);
    }
  }
}

1;

# -----------------------------------------------------------------------------
#
# CHANGES
#
# 21.04.2018 JB
# - prevent creation of client connection MSGCNT/TIME stat internals from FHEM dispatch
# - make FHEM device mode 'MANUAL' passive, i.e. set valve mode to 'OFF' to allow mode toggling between 'AUTO'/'OFF' (e.g. for weather control)
#   but keeping mode unchanged if set to 'MANUAL'
#
# 25.11.2017 JB
# - added disable attribute
#
# 02.09.2016 JB
# - renamed low battery shutdown mode from "LOW BAT" to "SHTDWN"
# - introduced new low battery warning mode "LOW BAT"
#
# -----------------------------------------------------------------------------


=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary WiFi controller device of a Gardena 1251 irrigation valve

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="GardenaValve"></a>
<h3>GardenaValve</h3>
<ul>
    <a name="GardenaValve"></a>
    <p>
    With this module you can control Gardena 01251 9 VDC solenoid irrigation valves via WiFi.<br>
    This is a client module that parses messages dispatched from a <a href="#GardenaBridge">GardenaBridge</a> device.
    <br>
    <p>

    <b>Define</b>
    <ul>
        <li>
            <code>define &lt;name&gt; GardenaValve &lt;IP address&gt;</code><br>
            <br>
            Creates a GardenaValve devices to control a single Gardena 01251 9 VDC solenoid irrigation valve.<br>
            This device is a message parser and requires a <a href="#GardenaBridge">GardenaBridge</a> device as message dispatcher to operate.<br>
        </li>
    </ul>
    <p>

    <b>Set</b>
    <ul>
      <li><b>on</b> - open valve once for <i>defaultDuration</i> starting at next communication (convenience method for MANUAL &lt;now + remaining wakeupPeriod&gt;)</li>
      <li><b>on-till &lt;startTime&gt;</b> - open valve once for <i>defaultDuration</i> starting at given startTime (YYYY-MM-DD hh:mm:ss)<br>
          <i>Note: The valve will not open if the operation time (startTime + defaultDuration) has already passed before next communication.</i>
      </li>
      <li><b>auto</b> - enable valve scheduler</li>
      <li><b>off</b> - close valve and disable valve scheduler with next communication</li>
      <li><b>manual</b> - same behaviour as off - can be used to prevent automatic control toggling between auto and off</li>
      <i>Note: It is (for security reasons) not possible to remotely override a manual push button operation at the valve controller.</i>
    </ul>
    <p>

    <b>Readings</b>
    <ul>
      <li><b>manualStart</b> - time the valve will be opened in MANUAL mode</li>
      <li><b>mode</b> - operation mode of the valve controller, may be OFF, MANUAL, AUTO or OVERRRIDE<br>
          OVERRIDE mode is activated by using the manual push button at the valve controller.<br>
      </li>
      <li><b>state</b> - state of the device, may be:
        <ul>
          <li>OFF - valve closed, scheduler disabled</li>
          <li>AUTO - valve closed, scheduler enabled</li>
          <li>ON - valve open</li>
          <li>UPDATING - last set command will be transmitted to valve controller at next wakeup</li>
          <li>LOW BAT  - valve controller battery voltage is low, valve operation will shut down soon</li>
          <li>SHUTDOWN - valve controller battery empty<br>
              <b>Warning: In SHUTDOWN state all valve operations are disabled. The valve controller will try to close an already open valve when entering SHUTDOWN state.</b>
          </li>
          <li>OFFLINE - valve controller has not communicated for more than 2 times the current wakeupPeriod</li>
          <li>INIT - FHEM device is initialized and waiting for data or commands</li>
          <li>DISABLED - FHEM device is disabled </li>
        </ul>
      </li>
      <li><b>valve</b> - state of the valve, may be CLOSED or OPEN<br>
          <i>Note: this reading is not valid if state is OFFLINE</i>
      </li>
      <li><b>time</b> - the current time of the valve controller, may be used to fine tune <i>timeScale</i></li>
      <li><b>timeOffset</b> - the time offset of the valve controller [s], may be used to fine tune <i>timeScale</i></li>
      <li><b>voltage</b> - the regulator voltage of the valve controller, should be 3.32 V with a fully charged battery</li>
      <li><b>openCount</b> - number of times the valve was opened since physical device was reset</li>
      <li><b>openCountOverall</b> - total number of times the valve was opened since FHEM device was reset</li>
      <li><b>openDuration</b> - total time [h] the valve was open since physical device was reset</li>
      <li><b>openDurationOverall</b> - total time [h] the valve was open since FHEM device was reset</li>
      <li><b>volumeOverall</b> - total estimated volume [m3] since volumeInitialized, delete reading to reinitialize</li>
      <li><b>volumeInitialized</b> - time the volume was initialized with a value above zero</li>
    </ul>
    <p>

    <b>Attributes</b>
    <ul>
      <li><b>batteryDays</b> - rough estimate of the maximum life of a 2600 mAh battery based on the communication wakeup period only, real battery life expectancy will be significantly lower (info)</li>
      <li><b>defaultDuration</b> - duration in seconds the valve will be opened when using the override button, the manual on command or a schedule entry with a duration of zero (5 ... 7200 seconds)</li>
      <li><b>programId</b> - auto generated ID for the current schedule to simplify change detection (internal)</li>
      <li><b>schedule</b> - The primary use of the valve controller is to run autonomously by a predefined schedule. This schedule can hold up to 32 entries.
          Each schedule entry consists of a day selector, a start time and a run duration.<br>
          <ul>
            <li><i>day selector</i>
              <ul>
                <li><b>all</b> - every day</li>
                <li><b>2nd</b> - every second day of the year</li>
                <li><b>3nd</b> - every third day of the year</li>
                <li><b>Sun, Mon, Tue, Wed, Thu, Fri, Sat</b> - specific day of the week</li>
              </ul>
            </li>
            <li><i>start time</i> - hh:mm (minute resolution)
            </li>
            <li><i>duration</i> - seconds (0, 5 ... 7200 seconds)<br>
              A duration value of 0 is treated specially by using the defaultDuration instead. This provides a simple way to change the duration without rewriting the schedule.
            </li>
          </ul>
          example: <code>( ('2nd', '06:30', 300), ('all', '22:00', 0), ('Sun', '00:00', 60) )</code><br>
          <i>Note: Overlapping entries will typically add up with a short interrupt in between, but this is not guaranteed.</i>
      </li>
      <li><b>timeSync</b> - If set to 1 the internal clock of the valve controller is time synchronized every time it communicates (default: enabled).
          Set to 0 if you want to fine tune the <i>timeScale</i> attribute for autonomous time precision.
      </li>
      <li><b>timeScale</b> - The valve controller has no RTC and estimates time by accumulating its wakeup period.
          A maximum of 2 decimal places are supported (-10.00 ... +10.00%, default: 3.75%). Smaller values let the time run faster. A slightly slower than realtime setting is preferable when time sync is enabled to avoid having the same time twice in short order. Skipping a few seconds forward with each time sync will cause missing scheduler events as long as their duration is longer than the skipped period. Set the time scale using this formula: 100*((1+oldTimeScale/100)*(1+timeOffset/wakeupPeriod) - 1). The precision can be improved by fine tuning this attribute over several cycles (set attribute <i>timeSync</i> to 0, check reading <i>time</i> and compare it with its timestamp).
      </li>
      <li><b>timeOffset</b> - The ESP8266 requires a few milliseconds to boot and shutdown that are not part of the runtime or the downtime (default 87 ms). Fine tuning this value will improve the RTC estimation when <i>timeSync</i> is disabled and the wakeup period is changed.
      </li>
      <li><b>batteryOffset</b> - The valve controller uses its internal ADC to read the regulated battery voltage. Because each ADC has an individual offset
          you must set this attribute once on 1st use when a fully charged battery is inserted, so that the reading <i>voltage</i> reads 3.32 Volt (-500 ... +500 mV).<br>
          <b>Warning: Improper setting of this attribute may disable low battery detection and may prevent closing an open valve.
             The Gardena 01251 9 VDC solenoid irrigation valve is a bistable/latching type and will not close by itself without applying electrical power.
             Always install an additional mechanical valve as backup.</b><br>
      </li>
      <li><b>wakeupPeriod</b> - The period in seconds the valve controller will wakeup and communicate to send an alive status and receive new commands (1 ... 3600 seconds).<br>
          <i>Note: The valve controller uses more than 3000 times its idle power when communicating via WiFi. Check attribute maxBatteryDays for an impact estimate.</i>
      </li>
      <li><b>averageFlow</b> - The average flow for estimating the total volume based on the valve open duration, keep undefined if volume calculation is not required (0 ... 100 l/min).
      </li>
      <li><b>disable</b> - If set to 1 the device is disabled (default: enabled).
      </li>
   </ul>
    <br>
</ul>

=end html

=cut
