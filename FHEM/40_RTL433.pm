# -----------------------------------------------------------------------------
# $Id: 40_RTL433.pm 3 2018-01-01 13:38:00Z jensb $
# -----------------------------------------------------------------------------

=encoding UTF-8

=head1 NAME

RTL433 - A FHEM Perl module to run rtl_433 and parse the output into readings.

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

use threads;
use threads::shared;
use Time::HiRes qw(usleep);
use Blocking;

use constant COMMAND => '/usr/local/bin/rtl_433 -l';

my %sets = (
  'bitLevel' => '5000',
);

=head1 FUNCTIONS

=head2 RTL433_Initialize($)

FHEM module I<Initialize> function, called before define and after each reload

=over

=item * param hash: hash of s RTL433 device

=back

=cut

sub RTL433_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}      = 'RTL433_Define';
  $hash->{UndefFn}    = 'RTL433_Undef';

  $hash->{ShutdownFn} = 'RTL433_Shutdown';

  $hash->{AttrFn}     = 'RTL433_Attr';
  $hash->{AttrList}   = "disable:0,1 sensors:textField-long bitLevel extraArguments " . $readingFnAttributes;

  Log3 'RTL433', 5, 'RTL433: RTL433_Initialize done';
}

=head2 RTL433_Reader($)

BlockingCall I<BlockingFn> callback, try to read output from rtl_433 process and send it to function L</RTL433_ReaderEvent($)> via telnet

=over

=item * param hash: hash of a RTL433 device

=item * return result required by function L</RTL433_ReaderFinished($)>

=back

ATTENTION: This method is executed in a different process than FHEM.
           The device hash is from the time of the process initiation.
           Any changes to the device hash or readings are not visible
           in FHEM.

=cut

sub RTL433_Reader($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash); # child does not need polling

  my $bitLevel = AttrVal($name, 'bitLevel', '5000');
  my $extraArguments = AttrVal($name, 'extraArguments', '-R12'); # R12=Oregon Scientific
  my $pid = open(FH, COMMAND . $bitLevel . " " . $extraArguments . " 2>&1|");
  if (defined($pid))
  {
    BlockingInformParent("RTL433_ReaderEvent", [$name, 'start', $pid], 0);
    while(<FH>)
    {
      my $message = $_;
      $message =~ s/\n/ /g; # replace newline with space
      BlockingInformParent("RTL433_ReaderEvent", [$name, 'data', $message], 0);
    }
    BlockingInformParent("RTL433_ReaderEvent", [$name, 'stop', $pid], 0);
  }
  else
  {
    BlockingInformParent("RTL433_ReaderEvent", [$name, 'error', 'failed to start rtl_433'], 0);
  }

  return $name;
}

=head2 RTL433_ReaderEvent($$;$)

receive data from BlockingCall via telnet by function L</RTL433_Reader($)>

=over

=item * param name: name of a RTL433 device

=item * param event: type of RTL433 event (start, data, stop, error)

=item * param params: parameters of event pending on event type, optional

=item * return C<undef>

=back

=cut

sub RTL433_ReaderEvent($$;$)
{
  my ($name, $event, $params) = @_;
  my $hash = $defs{$name};

  Log3 $hash, 5, "$name: RTL433_ReaderEvent $event $params";

  if ($event eq 'data')
  {
    RTL433_Read($hash, $params);
  }
  elsif ($event eq 'start')
  {
    Log3 $name, 3, "$name: RTL433_ReaderEvent process rtl_433 started (PID $params)";
    $hash->{PID} = $params;
    $hash->{STATE} = 'Started';
  }
  elsif ($event eq 'stop')
  {
    Log3 $name, 3, "$name: RTL433_ReaderEvent process rtl_433 stopped (PID $params)";
    $hash->{PID} = undef;
    $hash->{STATE} = 'Stopped';
  }
  elsif ($event eq 'error')
  {
    Log3 $name, 2, "$name: RTL433_ReaderEvent $params";
    $hash->{STATE} = "Error: $params";
  }
  else
  {
    Log3 $hash, 3, "$name: RTL433_ReaderEvent unsupported event '$event'";
  }

  return undef;
}

=head2 RTL433_ReaderFinished($)

BlockingCall I<FinishFn> callback

=over

=item * param name: name of RTL433 device

=back

=cut

sub RTL433_ReaderFinished($)
{
  my ($name) = @_;
  my $hash = $defs{$name};

  $hash->{PROCESSED} = '';
  $hash->{UNPROCESSED} = '';

  Log3 $hash, 5, "$name: RTL433_ReaderFinished";
}

=head2 isRunning($)

=over

=item * param name: PID of rtl_r33

=back

=cut

sub isRunning($)
{
  my ($pid) = @_;

  my $running = 0;
  if (defined($pid))
  {
    $running = kill(0, $pid);
  }

  return $running;
}

=head2 RTL433_Start($)

request to start rtl_433 process asynchronously

=over

=item * param hash: hash of a RTL433 device

=back

=cut

sub RTL433_Start($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: RTL433_Start start";

  # check RTL433 reader PID
  if (defined($hash->{PID}))
  {
    if (!isRunning($hash->{PID}))
    {
      Log3 $name, 5, "$name: RTL433_Start removing dead reader PID defined($hash->{PID}";
      $hash->{PID} = undef;
      $hash->{STATE} = 'Stopped';
      $hash->{PROCESSED} = '';
      $hash->{UNPROCESSED} = '';
    }
  }

  my $success = 0;
  if (!defined($hash->{PID}))
  {
    # start new RTL433 reader thread
    $hash->{STATE} = 'Starting';
    $hash->{PROCESSED} = '';
    $hash->{UNPROCESSED} = '';
    my $child = BlockingCall("RTL433_Reader", $hash, "RTL433_ReaderFinished", 0);
    if (defined($child))
    {
      $success = 1;
    }
    else
    {
      Log3 $name, 3, "$name: RTL433_Start failed to start rtl_433";
    }
  }
  else
  {
    Log3 $name, 5, "$name: RTL433_Start rtl_433 already running (PID $hash->{PID})";
    $success = 1;
  }

  Log3 $name, 5, "$name: RTL433_Start end";

  return $success;
}

=head2 RTL433_Stop($)

request rtl_433 process to stop

=over

=item * param hash: hash of a RTL433 device

=back

=cut

sub RTL433_Stop($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: RTL433_Stop start";

  my $running = 0;
  if (isRunning($hash->{PID}))
  {
    $running = kill(SIGKILL, $hash->{PID});
    if ($running)
    {
      # wait for thread to terminate
      while (isRunning($hash->{PID}))
      {
        usleep(20000); # 20 ms
      }
      Log3 $name, 5, "$name: RTL433_Stop rtl_433 (PID $hash->{PID}) stopped";
    }
  }
  else
  {
    Log3 $name, 5, "$name: RTL433_Stop rtl_433 not running";
  }

  Log3 $name, 5, "$name: RTL433_Stop end";
}

=head2 RTL433_Define($$)

FHEM module I<DefFn>

=over

=item * param hash: hash of a RTL433 device

=item * param def: module define parameters, will be ignored

=item * return undef on success or error message

=back

=cut

sub RTL433_Define($$)
{
  my ($hash, $def) = @_;
  my @param = split('[ \t]+', $def);

  if (int(@param) < 2)
  {
    return "too few parameters: define <name> RTL433";
  }

  my $name = $param[0];
  $hash->{NAME} = $name;

  Log3 $name, 5, "$name: RTL433_Define start";

  if (!defined($hash->{PID}))
  {
    $hash->{STATE} = 'Initialized';
  }

  $hash->{PROCESSED} = '';
  $hash->{UNPROCESSED} = '';

  RemoveInternalTimer($hash);

  Log3 $name, 5, "$name: RTL433_Define end";

  return undef;
}

=head2 RTL433_Poll($)

=over

=item * param hash: hash of a RTL433 device

=back

=cut

sub RTL433_Poll($) {
  my ($hash) =  @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: RTL433_Poll start";

  if ((!defined($hash->{PID}) || !isRunning($hash->{PID})) && $hash->{STATE} ne 'Starting')
  {
    if (!AttrVal($hash->{NAME}, "disable", 0))
    {
      RTL433_Start($hash);
    }
  }

  # Schedule next polling
  InternalTimer(gettimeofday() + 60, 'RTL433_Poll', $hash, 0);

  Log3 $name, 5, "$name: RTL433_Poll end";
}

=head2 RTL433_Notify($$)

FHEM module I<NotifyFn>, called after initialized or rereadcfg

=over

=item * param hash: hash of a RTL433 device

=item * param dev: hash of notifying device

=item * return undef on success or error message

=back

=cut

sub RTL433_Notify($$)
{
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  Log3 $name, 5, "$name: RTL433_Notify global"; # @{$dev->{CHANGED}}";

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday() + 1, "RTL433_Poll", $hash, 0);

  return undef;
}

=head2 RTL433_Shutdown($)

FHEM module I<ShutdownFn>, before shutdown

=over

=item * param hash: hash of a RTL433 device

=back

=cut

sub RTL433_Shutdown($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: RTL433_Shutdown start";

  RTL433_Stop($hash);

  Log3 $name, 5, "$name: RTL433_Shutdown end";
}

=head2 RTL433_Undef($)

FHEM module I<ShutdownFn>

=over

=item * param hash: hash of a RTL433 device

=back

=cut

sub RTL433_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: RTL433_Undef start";

  RTL433_Stop($hash);
  RemoveInternalTimer($hash);

  Log3 $name, 5, "$name: RTL433_Undef end";

  return undef;
}

=head2 RTL433_Read($)

process message received from rtl_433 process to update readings

=over

=item * param hash: hash of a RTL433 device

=item * param message: output from rtl_433

=back

=cut

sub RTL433_Read($$)
{
  my ($hash, $message) = @_;
  my $name = $hash->{NAME};

  $message =~ s/^\s+|\s+$//g;
  Log3 $name, 5, "$name: RTL433_Read received $message";
  if (defined($message) && $hash->{PROCESSED} ne $message)
  {
    my $processed = 0;
    my $sensorsAttribute = AttrVal($name, 'sensors', '');
    if (length($sensorsAttribute))
    {
      my $sensors;
      eval('$sensors = ' . $sensorsAttribute);
      foreach my $sensorName (keys %$sensors)
      {
        # device detection
        my $sensorConfig = $sensors->{$sensorName};
        my $deviceFilter = $sensorConfig->{'device'};
        if ($message =~ /$deviceFilter/)
        {
          Log3 $name, 5, "$name: RTL433_Read sensor $sensorName found, extracting ...";
          # value extraction
          my $readings = $sensorConfig->{'readings'};
          my $valuePattern = $sensorConfig->{'pattern'};
          my @values = $message =~ /$valuePattern/;
          if (scalar(@$readings) == scalar(@values))
          {
            readingsBeginUpdate($hash);
            for (my $i = 0; $i < @values; $i++)
            {
              Log3 $name, 5, "$name: RTL433_Read value $i $readings->[$i] = $values[$i]";
              my $scale = $sensorConfig->{'scale'.$readings->[$i]};
              my $offset = $sensorConfig->{'offset'.$readings->[$i]};
              if (defined($scale) || defined($offset))
              {
                # linear adjustment for numeric values
                $scale = 1 if !defined($scale);
                $offset = 0 if !defined($offset);
                readingsBulkUpdate($hash, $sensorName.$readings->[$i], $scale*$values[$i] + $offset);
              }
              else
              {
                # unadjusted and non-numeric values
                readingsBulkUpdate($hash, $sensorName.$readings->[$i], $values[$i]);
              }
            }
            readingsEndUpdate($hash, 1);

            $processed = 1;
            last;
          }
          else
          {
            Log3 $name, 4, "$name: RTL433_Read extraction failed, found " . scalar(@values) . " of " . scalar(@$readings) . " values";
          }
        }
      }
    }
    if ($processed)
    {
      $hash->{PROCESSED} = $message;
    }
    elsif (length($message))
    {
      $hash->{UNPROCESSED} =  $message . '|' . substr($hash->{UNPROCESSED}, 0, 256);
    }
  }
}

=head2 RTL433_Attr(@)

FHEM module I<AttrFn>

=over

=item * param command: "set" or "del"

=item * param name: name of a RTL433 device

=item * param attribute: attribute name

=item * param value: attribute value

=item * return C<undef> on success or error message

=back

=cut

sub RTL433_Attr(@)
{
  my ($cmd,$name,$attrName,$attrValue) = @_;
  my $hash = $defs{$name};

  my $msg = '';
  if ($cmd eq "set")
  {
    if ($attrName eq 'bitLevel')
    {
      my $valid = defined($attrValue) && looks_like_number($attrValue) && $attrValue > 0 && $attrValue <= 10000;
      if ($valid)
      {
        # restart rtl_433
        RTL433_Stop($hash);
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 3, 'RTL433_Poll', $hash, 0);
      }
      else
      {
        $msg = "attr $attrName must be a number between 1 and 10000";
      }
    }
    elsif ($attrName eq "disable" || $attrName eq 'extraArguments')
    {
      # restart rtl_433
      RTL433_Stop($hash);
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday() + 3, 'RTL433_Poll', $hash, 0);
    }
  }

  return ($msg) ? $msg : undef;
}

1;

# -----------------------------------------------------------------------------
#
# CHANGES
#
# 27.09.2015 jnsbyr
#   method _Reader: decode Oregon Scientific only
#   method _Read: added humidity offset support
#
# 15.11.2015 jnsbyr
#   method _ReaderEvent: return undef to prevent FHEM sending reply
#
# 15.12.2015 jnsbyr
#   method _Read: added humidity scale support
#
# 27.04.2016 jnsbyr
#   device filtering and value extraction made configurable
#
# 01.01.2018 jnsbyr
#   rtl_433 command line arguments made configurable
#
# -----------------------------------------------------------------------------


=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary run rtl_433 and parse output into readings

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="RTL433"></a>
<h3>RTL433</h3>
<ul>
  Tested with GiXa Technology DVB-T/DAB/FM USB 2.0 Stick (Realtek RTL2832U
  demodulator + Rafael Micro R820T tuner) on Raspberry Pi 2.0 / Raspbian 3.18. <br><br>

  To use this module you need to install:
  <ul>
    <li> <a href="https://osmocom.org/projects/rtl-sdr/wiki/Rtl-sdr">rtl-sdr</a> </li>
    <li> <a href="https://github.com/merbanan/rtl_433.git">rtl_433</a> </li>
  </ul> <br>

  Notes:
  <ul>
    <li> Low cost alternative for some RFXCOM applications.</li> <br>

    <li> Because rtl_433 has no sensor independent output format you need to adjust
         the property matching by setting the <code>sensors</code> attribute. In some
         cases you should also consider patching rtl_433 to adjust the output format to
         your requirements.</li> <br>

    <li> Receiver sensitivity range is slightly less than with a proprietary 433 MHz receiver.
         Antenna position and rtl_433 bit level must be adjusted individually for best results.
         To receive all available transmitters damping transmitters that are nearest to
         antenna should be considered.</li> <br>

    <li> This module is a FHEM wrapper for the rtl_433 application that is started as a
         separate process. It is not suitable for low powered platforms. Running rtl_433
         loads one Raspberry Pi 2.0 CPU core permanently at approximately 35% for processing
         the samples from the radio. Load can be slightly reduced by enabling only the required
         number of decoders with the <i>-R</i> parameter of rtl_433 using the
         <code>extraArguments</code> attribute.</li> <br>
  </ul> <br>

  Example: 
<pre><code>define RTL433 RTL433
attr RTL433 bitLevel 5000
attr RTL433 extraArguments -R12 -R16
attr RTL433 sensors { sensor1 => { device => 'THGR122N.*0x12', \
                                   readings => [ 'Battery', 'Temperature', 'Humidity' ], \
                                   pattern => 'channel.*rid.*battery (\w+).*Temp: (-?[\d\.]+).*Humidity: ([\d\.]+)', }, \
                      sensor2 => { device => 'Alecto.*Rain.*123', \
                                   readings => [ 'Rain', 'Battery' ], \
                                   pattern => 'Rain ([\d\.]+) mm.*Battery (\w+)', },
} </code></pre>
</ul> <br>

=end html

=cut
