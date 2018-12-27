########################################################################################
#
# $Id: 20_FRM_I2C.pm 5927 2014-05-21 21:56:37Z ntruchsess $
#
# FHEM module to read continuously from a I2C device connected to a Firmata device
#
########################################################################################
#
#  LICENSE AND COPYRIGHT
#
#  Copyright (C) 2013 ntruchess
#  Copyright (C) 2018 jensb
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

package main;

use strict;
use warnings;

#add FHEM/lib to @INC if it's not already included. Should rather be in fhem.pl than here though...
BEGIN {
  if (!grep(/FHEM\/lib$/,@INC)) {
    foreach my $inc (grep(/FHEM$/,@INC)) {
      push @INC,$inc."/lib";
    };
  };
};

use Device::Firmata::Constants  qw/ :all /;

#####################################

sub
FRM_I2C_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_I2C_Init";
  $hash->{UndefFn}   = "FRM_I2C_Undef";
  $hash->{AttrFn}    = "FRM_I2C_Attr";

  $hash->{AttrList}  = "IODev $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_I2C_Init($)
{
  my ($hash,$args) = @_;
  my $u = "wrong syntax: define <name> FRM_I2C address register numbytes";

  return $u if(int(@$args) < 3);

  $hash->{"i2c-address"} = @$args[0];
  $hash->{"i2c-register"} = @$args[1];
  $hash->{"i2c-bytestoread"} = @$args[2];

  if ($hash->{"i2c-bytestoread"} > 0) {
    eval {
      FRM_Client_AssignIOPort($hash);
      FRM_Client_FirmataDevice($hash)->i2c_read(@$args[0],@$args[1],@$args[2]);
    };
    if ($@) {
      $@ =~ /^(.*)( at.*FHEM.*)$/;
      $hash->{STATE} = "error initializing: ".$1;
      return "error initializing '".$hash->{NAME}."': ".$1;
    }
    return "error calling i2c_read: ".$@ if ($@);    
  } else {
    eval {
      FRM_Client_AssignIOPort($hash);
      FRM_Client_FirmataDevice($hash)->i2c_stopreading($hash->{"i2c-address"});
    };
  }
  
  return undef;
}

sub
FRM_I2C_Undef($$) {
  my ($hash, $arg) = @_;

  eval {
    FRM_Client_FirmataDevice($hash)->i2c_stopreading($hash->{"i2c-address"});
  };

  return FRM_Client_Undef($hash, $arg);
}

sub
FRM_I2C_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $main::defs{$name};
  eval {
    if ($command eq "set") {
      ARGUMENT_HANDLER: {
        $attribute eq "IODev" and do {
          if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $value)) {
            FRM_Client_AssignIOPort($hash,$value);
            FRM_Init_Client($hash) if (defined ($hash->{IODev}));
          }
          last;
        };
      }
    }
  };
  if ($@) {
    $@ =~ /^(.*)( at.*FHEM.*)$/;
    $hash->{STATE} = "error setting $attribute to $value: ".$1;
    return "cannot $command attribute $attribute to $value for $name: ".$1;
  }
}

1;

=pod

  CHANGES

  23.12.2018 jensb
    o issue I2C stop reading command if device is initialized with zero byte count or is deleted
    o updated module help

=cut


=pod
=item device
=item summary Firmata: read I2C register
=item summary_DE Firmata: I2C Register lesen
=begin html

<a name="FRM_I2C"></a>
<h3>FRM_I2C</h3>
<ul>
  This module reads a specified number of bytes from a I2C device that is wired to a <a href="http://www.firmata.org">Firmata device</a>. It requires a defined <a href="#FRM">FRM</a> device to work.<br><br>
  
  I2C bus support must be enabled on the FRM device by setting the attribute <code>i2c-config</code> to a valid value. The requested bytes will be read periodically depending on the attribute <code>sampling-interval</code> of the FRM device as soon as the Firmata device is connected.<br><br>

  <a name="FRM_I2Cdefine"></a>
  <b>Define</b><br><br>
  
  <code>define &lt;name&gt; FRM_I2C &lt;i2c-address&gt; &lt;register&gt; &lt;bytes-to-read&gt;</code> <br><br>
    
  <ul>
    <li>i2c-address is the I2C bus address (decimal) of the I2C device</li>
    <li>register is the I2C register address (decimal) to start reading bytes from</li>
    <li>bytes-to-read is the number of bytes to read from the I2C device</li>
  </ul><br>

  <a name="FRM_I2Cset"></a>
  <b>Set</b><br>
  <ul>
    N/A
  </ul><br>

  <a name="FRM_I2Cget"></a>
  <b>Get</b><br>
  <ul>
    N/A
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
