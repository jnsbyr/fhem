################################################################################
# $Id: 20_FRM_I2C.pm 5927 2018-12-29 17:32:00Z jensb $
################################################################################

=encoding UTF-8

=head1 NAME

FHEM module to read continuously from and to write to a I2C device connected to
a Firmata device

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2013 ntruchess
Copyright (C) 2018 jensb

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

use Device::Firmata::Constants qw(:all);
use Scalar::Util qw(looks_like_number);

#add FHEM/lib to @INC if it's not already included. Should rather be in fhem.pl than here though...
BEGIN {
  if (!grep(/FHEM\/lib$/,@INC)) {
    foreach my $inc (grep(/FHEM$/,@INC)) {
      push @INC,$inc."/lib";
    };
  };
};

#####################################

sub
FRM_I2C_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FRM_Client_Define";
  $hash->{InitFn}   = "FRM_I2C_Init";
  $hash->{UndefFn}  = "FRM_I2C_Undef";
  $hash->{AttrFn}   = "FRM_I2C_Attr";
  $hash->{GetFn}    = "FRM_I2C_Get";
  $hash->{SetFn}    = "FRM_I2C_Set";
  $hash->{I2CRecFn} = "FRM_I2C_Receive";

  $hash->{AttrList} = "IODev $main::readingFnAttributes";

  main::LoadModule("FRM");
}

sub
FRM_I2C_Init($)
{
  my ($hash, $args) = @_;
  my $name = $hash->{NAME};

  my $usage = "usage: define <name> FRM_I2C address register numbytes";
  return $usage if (int(@$args) < 3);

  $hash->{I2C_Address}       = @$args[0];
  $hash->{I2C_READ_REGISTER} = @$args[1];
  $hash->{I2C_READ_BYTES}    = @$args[2];

  # stop reading
  if ($main::init_done && defined($hash->{IODev})) {
    eval {
      FRM_Client_FirmataDevice($hash)->i2c_stopreading($hash->{I2C_Address});
    };
  } 
  
  # assign IODev
  eval {
    FRM_Client_AssignIOPort($hash);
  };
  if ($@) {
    $@ =~ /^(.*)( at.*FHEM.*)/;
    readingsSingleUpdate($hash, 'state', "error initializing IODev: $1", 1);
    return $1;
  }
  
  # start reading
  if ($hash->{I2C_READ_BYTES} > 0) {
    eval {
      FRM_Client_FirmataDevice($hash)->i2c_read(@$args[0], @$args[1], @$args[2]);
    };
    if ($@) {
      $@ =~ /^(.*)( at.*FHEM.*)/;
      readingsSingleUpdate($hash, 'state', "error initializing periodic I2C read: $1", 1);
      return $1;
    }
  }
  
  readingsSingleUpdate($hash, 'state', 'Initialized', 1);  
  return undef;
}

sub
FRM_I2C_Undef($$)
{
  my ($hash, $arg) = @_;

  # stop reading
  eval {
    FRM_Client_FirmataDevice($hash)->i2c_stopreading($hash->{I2C_Address});
  };

  return FRM_Client_Undef($hash, $arg);
}

sub
FRM_I2C_Attr($$$$)
{
  my ($command, $name, $attribute, $value) = @_;
  my $hash = $main::defs{$name};
  
  if (defined ($command)) {
    eval {
      if ($command eq "set") {
        ARGUMENT_HANDLER: {
          $attribute eq "IODev" and do {          
            if ($main::init_done) {
              # stop reading on old IODev
              if (defined($hash->{IODev}) && $hash->{IODev}->{NAME} ne $value) {
                eval {
                  FRM_Client_FirmataDevice($hash)->i2c_stopreading($hash->{I2C_Address});
                };
              }
              # assign new IODev and init FRM client
              if (!defined($hash->{IODev}) || $hash->{IODev}->{NAME} ne $value) {
                FRM_Client_AssignIOPort($hash, $value);
                if (!defined($hash->{IODev}) || $hash->{IODev}->{NAME} ne $value) {
                  die "$value not valid";
                }
                FRM_Init_Client($hash) if (defined ($hash->{IODev}));
              }
            }
            last;
          };
        }
      }
    };
    if ($@) {
      $@ =~ /^(.*)( at.*FHEM.*)/;
      readingsSingleUpdate($hash, 'state', "$command attribute $attribute error: " . $1, 1);
      return "$command attribute $attribute error: " . $1;
    }
  } else {
    return "no command specified";
  }

  return undef;
}

sub
FRM_I2C_Get($@)
{
  my ($hash, @parameters) = @_;
  my $name = $hash->{NAME};

  my $commandSelection = 'choose one of register:textField';
  if (scalar(@parameters) < 2 || !defined($parameters[1])) {
    return "unknown command, $commandSelection";
  }

  my $command = $parameters[1];
  if ($command eq 'register') {
    my $usage = "usage: get $name register &lt;register&gt; [&lt;bytes-to-read&gt;]";
    if (scalar(@parameters) == 3 || scalar(@parameters) == 4) {
      my $register = $parameters[2];
      my $numberOfBytes = scalar(@parameters) == 4? $parameters[3] : 1;
      if (looks_like_number($register) && $register >= 0 && looks_like_number($numberOfBytes) && $numberOfBytes > 0) {
        my $iodev = $hash->{IODev};
        my %package = (direction  => 'i2cread',
                       i2caddress => $hash->{I2C_Address},
                       reg        => $register,
                       nbyte      => $numberOfBytes
                      );
        eval {
          CallFn($iodev->{NAME}, 'I2CWrtFn', $iodev, \%package);
        };
        if ($@) {
          $@ =~ /^(.*)( at.*FHEM.*)/;
          return "failed getting $command $register: " . $1;
        }
        my $sendStat = $package{$iodev->{NAME} . '_SENDSTAT'};
        if (defined($sendStat) && $sendStat ne 'Ok') {
          return "failed getting $command $register: $sendStat";
        }
      } else {
        return $usage;
      }
    } else {
      return $usage;
    }
  } else {
    return "unknown command $command, $commandSelection";
  }

  return '';
}

sub
FRM_I2C_Set($@)
{
  my ($hash, @parameters) = @_;
  my $name = $hash->{NAME};

  my $commandSelection = 'choose one of register:textField';
  if (scalar(@parameters) < 2 || !defined($parameters[1])) {
    return "unknown command, $commandSelection";
  }

  my $command = $parameters[1];
  if ($command eq 'register') {
    my $usage = "usage: set $name register <register> <byte> [<byte> ... <byte>]";
    if (scalar(@parameters) >= 4) {
      my $register = $parameters[2];
      splice(@parameters, 0, 3);
      if (looks_like_number($register) && $register >= 0 && looks_like_number($parameters[0]) && $parameters[0] >= 0) {
        my $iodev = $hash->{IODev};
        my %package = (direction  => 'i2cwrite',
                       i2caddress => $hash->{I2C_Address},
                       reg        => $register,
                       data       => join(' ', @parameters)
                      );
        eval {
          CallFn($iodev->{NAME}, 'I2CWrtFn', $iodev,  \%package);
        };
        if ($@) {
          $@ =~ /^(.*)( at.*FHEM.*)/;
          return "failed setting $command $register: " . $1;
        }
        my $sendStat = $package{$iodev->{NAME} . '_SENDSTAT'};
        if (defined($sendStat) && $sendStat ne 'Ok') {
          return "failed setting $command $register: $sendStat";
        }
      } else {
        return $usage;
      }
    } else {
      return $usage;
    }
  } else {
    return "unknown command $command, $commandSelection";
  }

  return undef;
}

sub
FRM_I2C_Receive($$)
{
  my ($hash, $clientmsg) = @_;
  my $name = $hash->{NAME};

  my $iodevName = $hash->{IODev}->{NAME};
  my $sendStat = defined($iodevName) && defined($clientmsg->{$iodevName . '_SENDSTAT'})? $clientmsg->{$iodevName . '_SENDSTAT'} : '?';

  if ($sendStat ne 'Ok') {
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash, 'state', "error: $sendStat", 1);
    readingsEndUpdate($hash, 1);
  } elsif (defined($clientmsg->{direction}) && $clientmsg->{direction} eq 'i2cread' &&
           defined($clientmsg->{reg}) && defined($clientmsg->{received})) {
    my @raw = split(' ', $clientmsg->{received});
    my @values = split(' ', ReadingsVal($name, 'values', ''));
    while (scalar(@values) < 256) {
      push(@values, 0);
    }
    splice(@values, $clientmsg->{reg}, scalar(@raw), @raw);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'values', join (' ', @values), 1);
    readingsBulkUpdateIfChanged($hash, 'state', 'active', 1);
    readingsEndUpdate($hash, 1);
  }

  return undef;
}

1;

# -----------------------------------------------------------------------------
#
# CHANGES
#
# 28.12.2018 jensb
#   o moved I2C receive processing from FRM module to FRM_I2C module
#   o added I2C read function "get register"
#   o added I2C write function "set register"
#   o improve live modification of IODev
#
# 23.12.2018 jensb
#   o issue I2C stop reading command if device is initialized with zero byte count or is deleted
#   o updated module help
#
# -----------------------------------------------------------------------------

=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary Firmata: read/write I2C register

=item summary_DE Firmata: I2C Register lesen/schreiben

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="FRM_I2C"></a>
<h3>FRM_I2C</h3>
<ul>
  This module provides read and write capabilities for an I2C device that is wired to a <a href="http://www.firmata.org">Firmata device</a>. It requires a defined <a href="#FRM">FRM</a> device to work. I2C bus support must be enabled on the FRM device by setting the attribute <code>i2c-config</code> to a valid value.<br><br>

  If periodic reading is enabled the requested bytes will be updated depending on the attribute <code>sampling-interval</code> of the FRM device as soon as the Firmata device is connected.<br><br>

  <a name="FRM_I2Cdefine"></a>
  <b>Define</b><br><br>

  <code>define &lt;name&gt; FRM_I2C &lt;i2c-address&gt; &lt;register&gt; &lt;bytes-to-read&gt;</code> <br><br>

  <ul>
    <li>i2c-address is the I2C bus address (decimal) of the I2C device</li>
    <li>register is the I2C register address (decimal) to start reading bytes from</li>
    <li>bytes-to-read is the number of bytes to read periodically from the I2C device, the maximum number of bytes that can be read at the same time is limited by the Firmata firmware, the I2C device capabilities and the <code>sampling-interval</code> attribute of the FRM device, set to zero to disable periodic reading</li>
  </ul><br>

  <a name="FRM_I2Cget"></a>
  <b>Get</b><br>
  <ul>
    <li><code>register &lt;register&gt; [&lt;bytes-to-read&gt;]</code><br>
      request single asynchronous read of the specified number of bytes from the I2C register<br>
      bytes-to-read defaults to 1 if not specified, the maximum number of bytes that can be read at the same time is limited by the Firmata firmware and the I2C device capabilities
    </li>
  </ul><br>

  <a name="FRM_I2Cset"></a>
  <b>Set</b><br>
  <ul>
    <li><code>register &lt;register&gt; &lt;byte&gt; [&lt;byte&gt; ... &lt;byte&gt;]</code><br>
      write the space separated list of byte values to the specified I2C register
    </li>
  </ul><br>

  <a name="FRM_I2Cattr"></a>
  <b>Attributes</b><br>
  <ul>
    <li><a href="#IODev">IODev</a><br>
      specify which <a href="#FRM">FRM</a> to use (optional, only required if there is more than one FRM device defined)
    </li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul><br>

  <a name="FRM_I2Creadings"></a>
  <b>Readings</b><br>
  <ul>
    <li>values<br>
      space separated list of 256 byte register image using decimal values - may be preset to any value, only the requested bytes will be updated
    </li>
  </ul><br>
</ul><br>

=end html

=cut
