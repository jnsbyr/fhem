# -----------------------------------------------------------------------------
# $Id: 68_GardenaBridge.pm 3 2018-04-21 14:46:00Z jensb $
# -----------------------------------------------------------------------------

=encoding UTF-8

=head1 NAME

GardenaBridge - A FHEM Perl TCP/IP server gateway for one or more WiFi 
controllers of a Gardena 1251 irrigation valve.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015 Jens B.

All rights reserved

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package main;

use strict;
use warnings;

use Date::Parse;
use DateTime;
use JSON;
use POSIX qw(strftime);
use TcpServerUtils;
use Time::HiRes qw(gettimeofday);
use Try::Tiny;

sub GardenaBridge_Initialize($)
{
  my ($hash) = @_;

  $hash->{Clients} = 'GardenaValve';

  $hash->{DefFn}    = 'GardenaBridge_Define';
  $hash->{UndefFn}  = 'GardenaBridge_Undef';
  $hash->{ReadFn}   = 'GardenaBridge_Read';

  $hash->{AttrList} = $readingFnAttributes;
}

sub GardenaBridge_Define($$)
{
  my ($hash, $def) = @_;

  my ($name, $type, $port) = split("[ \t]+", $def);

  if (!defined($port))
  {
    return "Usage: define <name> GardenaBridge [IPV6:]<port>";
  }

  TcpServer_Close($hash);
  my $ret = TcpServer_Open($hash, $port, "0.0.0.0");
  if ($ret) {
    Log3($hash, 1, "Error: $ret");
    return $ret;
  }
}

sub GardenaBridge_Undef($$)
{
  my ($hash, $arg) = @_;
  return TcpServer_Close($hash);
}

sub GardenaBridge_Read($)
{
  my ($chash) = @_;           # client session hash
  my $cname = $chash->{NAME}; # client info

  if ($chash->{SERVERSOCKET})
  {
    # accept and create a module child
    TcpServer_Accept($chash, "GardenaBridge");
  }
  else
  {
    # read from TCP client connect descriptor
    my $hash = $defs{$chash->{SNAME}};
    my $buffer;
    my $ret = sysread($chash->{CD}, $buffer, 256);
    if (!defined($ret) || $ret <= 0)
    {
      # close TCP client connection
      CommandDelete(undef, $cname);
      return;
    }

    # dispatch message to client module for processing
    my %addvals;
    my $ip = $chash->{PEER};
    Dispatch($chash, "$ip:$buffer", \%addvals);
  }
}

1;

=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary TCP/IP server gateway for one or more WiFi controllers of a Gardena 1251 irrigation valve

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="GardenaBridge"></a>
<h3>GardenaBridge</h3>
<ul>
    <a name="GardenaBridge"></a>
    <p>
    This module provides a brige between FHEM and multiple Gardena 01251 9 VDC solenoid irrigation valves.
    It acts as a TCP/IP server for the WiFi solenoid controllers.<br>
    The Gardena valves must be equipped with JB's WiFi solenoid controller to enable WiFi access.
    Each Gardena valve can be controlled individually using a <a href="#GardenaValve">GardenaValve</a> module.
    <br>
    <br>
    <b>Requirements:</b><br>
    <ul>
        <li>Gardena 01251 9 VDC solenoid irrigation valve<br>
        </li>
        <li>JB's WiFi solenoid controller<br>
            While Gardena sells only a standalone solution for the 01251 solenoid irrigation valve there is a
            ESP8266 based project from JB (Hardware + Firmware) to provide battery powered remote control via WiFi.
            The components for one WiFi solenoid controller including a Li-Ion battery amount to approximately 60 EUR.
            The assembly of this WiFi solenoid controller requires A) a solid talent with a soldering iron for the PCB,
            B) integrating the PCB in a water tight enclosure with a RCA plug and C) several hours of patience for A and B,
            configuration, testing and debugging not included.<br>
            <i>Note: The Gardena 13554 solenoid irrigation valve is a non latching valve and requires 24 VAC
            and is therefore not compatible with this WiFi solenoid controller!</i>
        </li>
        <li>Li-Ion battery and charger<br>
            To power up the WiFi solenoid controller a type 18650 Li-Ion battery and a compatible charger is needed.
            Depending on the configurable communication wakeup period, the WiFi availability, the user defined switching program, the quality of the battery
            and the environmental conditions the life of a fully charged battery may vary significantly. The attribute batteryDays of the GardenaValve module
            gives a rough estimate depending on the communication wakeup period only (about 10 days for 15 seconds, more than a year for 900 seconds).<br>
            <i>Note: The WiFi solenoid controller uses more than 2000 times its idle power when communicating via WiFi.</i>
        </li>
        <li>USB/TTL adapter<br>
            To be able to flash/update the firmware of the WiFi solenoid controller an USB/TTL converter (e.g. with CP2102 chip) and 4 wires are required.
        </li>
        <li>PC with ESP8266 flash tool<br>
            To flash the firmware for the WiFi solenoid controller a flash tool for the ESP8266 is required (e.g. <a href="https://github.com/nodemcu">NodeMCU-Flasher</a>).
        </li>
        <li>WiFi access point<br>
            For the WiFi solenoid controller to connect to FHEM you need an IEEE 802.11 b/g/n WiFi access point with PSK authentication as gateway.
        </li>
        <li>Smartphone with SmartConfig App<br>
            To flash the WiFi access point credentials into the WiFi solenoid controller you need a smartphone and a SmartConfig App.<br>
            <i>Note: This feature is not yet implemented! Currently the WiFi AP credentials and the FHEM server IP address are configured by recompiling the firmware.</i>
        </li>
        <li>FHEM module GardenaBridge<br>
            To communicate with the WiFi solenoid controller the FHEM module <a href="#GardenaBridge">GardenaBridge</a> must be configured first.
        </li>
    </ul>
    <p>

    <b>Define</b>
    <ul>
        <li>
            <code>define &lt;name&gt; GardenaBridge &lt;port&gt;</code><br>
            <br>
            Creates a GardenaBridge devices with a TCP/IP server that listens on the specified port.<br>
            This device provides IODev support to <a href="#GardenaValve">GardenaValve</a> modules.<br>
            <i>Note: depending on your FHEM server setup you may need to open this port in your firewall rules.</i>
        </li>
    </ul>
    <p>

</ul>

=end html

=cut
