#!/usr/bin/perl

# ============================================================================
# Name        : s1_wm_ttn_fetchUnpack.pl
# Author      : Andy Maginnis
# Version     : 1.0.0
# Copyright   : MIT (See below)
# Description : TTN data store fetch and unpack script
#
# Written in PERL as its avaible on most/all *nix/OSX systems. Minimal 
# packages required, you may need JSON.
# This is intended for use in debuging data flow when adding devices to the
# TTN network. You can pull data using the CURL swagger API, decode the 
# BASE64 data and dump the resulting data structure.
# 
# If you have a windop windmeter you can pull the data for analysis/plotting
# of to test packet decoding.
#
# You can roll your own decode of your device, removing and replacing the 
# windop code. We could make this more generic and dynamically load modules
# but at present this is a KISS script to check data is arriving at TTN as 
# we expect.
#
# ============================================================================
# 
# MIT License
# 
# Copyright (c) 2017 Andy Maginnis
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# ============================================================================

use strict;
use MIME::Base64 qw( encode_base64 decode_base64 );
use File::Path qw(make_path);
use Getopt::Long;
use Data::Dumper;
use DateTime;
use JSON; 
use FindBin qw($Bin);

##-----------------------------------------------------------------------------
## Script start
##-----------------------------------------------------------------------------
my $cfgRef = processCommandLine();

if ($cfgRef->{listDevices}) {

  print "\n   Avaiable devices are: (JSON List returned)\n\n";
	print runOsCommandGetOutput(retTtndDevices($cfgRef)) . "\n";

	exit();

} else {

   if ($cfgRef->{selectDevice} ne "") {

      my $noOfPackets = 0 ;

      my $dt1 = DateTime->now( time_zone => 'UTC' );
   
      my $ttnDataRef = queryTtndReturnHashRef($cfgRef);

      $noOfPackets += convertAllRawBase64Packets($ttnDataRef);

      print Dumper $ttnDataRef if($cfgRef->{dump});

      # Remove and replace this next call for non wind op TTN use
      my $outFile = runWindOpUnpack($ttnDataRef, $cfgRef) if($cfgRef->{runWm});

      plotData($outFile) if($cfgRef->{plot});

      my $dt2 = DateTime->now( time_zone => 'UTC' ) - $dt1;

      printf("---TTN Fetch&Process %d packets in %ds.\n", $noOfPackets, $dt2->seconds);

   } # else do nothing? print help?

}

##-----------------------------------------------------------------------------
## Deal with the command line
##-----------------------------------------------------------------------------
sub processCommandLine {
   my %cfg;

   my $username = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
   $cfg{duration}     = "1h";
   $cfg{listDevices}  = 0;
   $cfg{selectDevice} = "";
   $cfg{outdirectory} = "/Users/$username/windop/ttn/wmOutData/";
   $cfg{help}         = 0;
   $cfg{info}         = 0;
   $cfg{quiet}        = 0;
   $cfg{plot}         = 0;
   $cfg{dump}         = 0;
   $cfg{runWm}        = 0;
   $cfg{curl}         = 0;
   $cfg{ttnkeys}      = "/Users/$username/wm_ttn_fetchUnpack.keys";

   GetOptions(
    "listDevices"    => \$cfg{listDevices}, # List what divices are avaiable 
    "duration=s"     => \$cfg{duration},    # 1h, 2d etc. As defined by Swagger
    "selectDevice=s" => \$cfg{selectDevice},# 
    "outdirectory=s" => \$cfg{outdirectory},# 
    "ttnkeysFile=s"  => \$cfg{ttnkeys},     # 
    "help"           => \$cfg{help},        # 
    "quiet"          => \$cfg{quiet},       # 
    "plot"           => \$cfg{plot},        # 
    "curl"           => \$cfg{curl},        # 
    "runWm"          => \$cfg{runWm},       # 
    "info"           => \$cfg{info},        # 
    "dump"           => \$cfg{dump}         # 
   );

   if ($cfg{help}) {
      print "
   TTN data store fetch and unpack script

      -listDevices           : Show devices we can get data for, queries TTN
      -selectDevice=s        : Get data for a device as shown by listDevices, queries TTN
      -duration=s            : Duration, 1h, 2d etc. as SWAGGER API
      -outdirectory=s        : Output CSV location, $cfg{outdirectory}
      -runWm                 : Run the WINDOP unpack/CsvGeneration
      -ttnkeysFile=s         : File to the TTN keys required by SWAGGER. You must create & populate this.
                               Defaults to a file in your HOME directory
                               $cfg{ttnkeys}
      -quiet                 : Dont print the data decode statements
      -plot                  : Call the s3 python plot script on the downloaded data.
      -dump                  : Dumps the packet data info & working data Hash. 
      -help                  : Prints this
      -info                  : Prints script dev info
      -curl                  : Show the curl command & exit once run.

## To fetch and process windop data use,
wm_ttn_fetchUnpack.pl -sel 00 -dur 3d -runWm

";
      exit();
   }


   if ($cfg{info}) {
print '

Using -dump will display the unpacked content of the TTN messages.
The example below shows the base64 and the decoded string. An array is 
created containing the byte values of the string in the order 0 -> N

>>> wm_ttn_fetchUnpack.pl -sel 00 -dur 10m -dum

---Base64 conversion packets = 3 in 0s
---Dev: 00 ID:     0 2017-08-26T11:05:01.371449068Z Type:4
---Dev: 00 ID:     1 2017-08-26T11:05:10.315692426Z Type:5
---Dev: 00 ID:     2 2017-08-26T11:10:22.273853271Z Type:4
---Unpack WM868 data packets = 3 in 0s
$VAR1 = [
          {
            \'\time\' => \'2017-08-26T11:05:01.371449068Z\',
            \'device_id\' => \'00\',
            \'decoded\' => \'042ebbd2187e4d01fa01000000010d01fa01000015016201f702fd0067010501fa0100004901a101f702fd004b01\',
            \'raw\' => \'BC670hh+TQH6AQAAAAENAfoBAAAVAWIB9wL9AGcBBQH6AQAASQGhAfcC/QBLAQ==\',
            \'bytes\' => [
                         4,
                         46,
                         187,
                         210,
                         ..........
                         36,
                         1
                       ]
          }
        ];
$VAR1 = {
         \'00\' => {
                                    \'20170826110900\' => {
                                                          \'ws\' => \'2.95\',
                                                          \'wsm\' => \'0\',
                                                          \'wsa\' => \'7.59\',
                                                          \'wd\' => 299
                                                        },
                  }
        };
';

      exit();
   }

   return \%cfg;
}

##-----------------------------------------------------------------------------
###############################################################################
## WINDOP use functions
## Unpack the packet types
## Export to various formats, CSV
###############################################################################
##-----------------------------------------------------------------------------

##-----------------------------------------------------------------------------
## Perform all the WIND OP operations
##-----------------------------------------------------------------------------
sub runWindOpUnpack {
   my ($ttnDataRef, $cfgRef) = @_;

   my %resHash;

   unpackWm868Data($ttnDataRef, \%resHash, $cfgRef->{selectDevice});

   print Dumper \%resHash if($cfgRef->{dump});

   return generateCsvOutput($cfgRef, \%resHash);

}

##-----------------------------------------------------------------------------
## Generate a CSV of the data. Manual dump to control the field formatting.
##-----------------------------------------------------------------------------
sub generateCsvOutput {
  my ( $cfgRef, $resHash ) = @_;

     my $oFormat = "time,ws,wsa,wsm,wd,tmp,pres,hum,bv,\n";
     my $hRef = $resHash->{$cfgRef->{selectDevice}};
     foreach my $time (sort {$a <=> $b} keys ( %{$hRef} )) {
        $oFormat .= "$time,";
        $oFormat .= (exists $hRef->{$time}{ws})   ? "$hRef->{$time}{ws},"   : ",";
        $oFormat .= (exists $hRef->{$time}{wsa})  ? "$hRef->{$time}{wsa},"  : ",";
        $oFormat .= (exists $hRef->{$time}{wsm})  ? "$hRef->{$time}{wsm},"  : ",";
        $oFormat .= (exists $hRef->{$time}{wd})   ? "$hRef->{$time}{wd},"   : ",";
        $oFormat .= (exists $hRef->{$time}{tmp})  ? "$hRef->{$time}{tmp},"  : ",";
        $oFormat .= (exists $hRef->{$time}{pres}) ? "$hRef->{$time}{pres}," : ",";
        $oFormat .= (exists $hRef->{$time}{hum})  ? "$hRef->{$time}{hum},"  : ",";
        $oFormat .= (exists $hRef->{$time}{bv})   ? "$hRef->{$time}{bv},"   : ",";
        $oFormat .= "\n";
     }
     print ("$oFormat\n") if (! $cfgRef->{quiet});

     if ( !-e $cfgRef->{outdirectory} ) {
        make_path($cfgRef->{outdirectory});
     }

     my $csvFName =  "$cfgRef->{outdirectory}/ttn_data_$cfgRef->{selectDevice}";
     $csvFName    .= "_$cfgRef->{duration}";
     $csvFName    .= "_" . getTimeForDataPacket();
     $csvFName    .= ".csv";
     printf("Writing data to $csvFName\n");
     writeToFile( $csvFName, $oFormat);

     return $csvFName;

}

##-----------------------------------------------------------------------------
## Unpack the time bytes
##-----------------------------------------------------------------------------
sub unpack_WindOpMinuteTime {
   my ( $byteRef, $timeRef ) = @_;

    my $length = 4;        # 4 Byte mode
    $timeRef->{Seconds}=0; # Seconds always 0 in 4 byte mode

    # // Remember LSByte first
    # // HHmm_mmmm
    $timeRef->{Minutes} = $byteRef->[2] & 0x3F;
    $timeRef->{Hours}  = ($byteRef->[2] & 0xC0) >> 6;

    # // DDDD_DHHH
    $timeRef->{Hours} += (($byteRef->[3] & 0x7) << 2);
    $timeRef->{DayOfMonth} = ($byteRef->[3] & 0xF8) >> 3;

    # // YYYY_MMMM
    $timeRef->{Month} = ($byteRef->[4] & 0x0F);
    $timeRef->{Year} = ($byteRef->[4] & 0xF0) >> 4;

    # // EYYY_YYYY
    $timeRef->{Year} += ($byteRef->[5] & 0x7F) << 4;

    if (($byteRef->[5] & 0x80) == 0x80) {
        $timeRef->{Year} += ($byteRef->[6] & 0xC0) << 5;
        $timeRef->{Seconds} = $byteRef->[6] & 0x3F;
        $length = 5;
    }

    # Create a time object for the unpacket time. 
    $timeRef->{dt} = DateTime->new(
      time_zone => 'UTC',
      year      => $timeRef->{Year},
      month     => $timeRef->{Month},
      day       => $timeRef->{DayOfMonth},
      hour      => $timeRef->{Hours},
      minute    => $timeRef->{Minutes},
      second    => $timeRef->{Seconds}
    );

    return $length;

}

##-----------------------------------------------------------------------------
## Unpack data packet 004
##-----------------------------------------------------------------------------
sub call_packetUnpack_004 {
   my ( $byteRef, $resRef, $device ) = @_;
   
   my %time;
   my $packetCount  = 0;
   my $packetLength = $byteRef->[1];

   ## Get the time and calculate the offset for the time in the data buffer
   ## Adjust the buffer for the packet header
   my $dataOffset   = unpack_WindOpMinuteTime($byteRef, \%time);
   $dataOffset += 2;

   ## Calculate the packet length based in the repetitons of data
   $packetLength -= $dataOffset;
   $packetLength -= 2;
   $packetLength /= 8;
   
   ## From C golden reference for pack
   # outBuffer[0] = readingsIn->ws & 0x00FF;            // LSB Wind speed, Average over 1 minute
   # outBuffer[1] = (readingsIn->ws & 0xFF00) >> 8;     // MSB
   # outBuffer[2] = readingsIn->wsx & 0x00FF;           // Wind speed max measured over 1 second
   # outBuffer[3] = (readingsIn->wsx & 0xFF00) >> 8;    // during the last averaging period
   # outBuffer[4] = readingsIn->wsm & 0x00FF;           // Wind speed min measured over 1 second
   # outBuffer[5] = (readingsIn->wsm & 0xFF00) >> 8;    // during the last averaging period
   # outBuffer[6] = readingsIn->wd & 0x00FF;            // Wind Direction
   # outBuffer[7] = (readingsIn->wd & 0xFF00) >> 8;     //

   for ($packetCount = 0; $packetCount < $packetLength ; $packetCount++) {
      
      my $base = $dataOffset + ($packetCount * 8);
      $time{dt}->add( minutes => 1 );
      my $timeStr = $time{dt}->ymd('') . $time{dt}->hms('');

      $resRef->{$device}{$timeStr}{ws}  = 0.01 * (($byteRef->[$base + 0]) + ($byteRef->[$base + 1]<<8));
      $resRef->{$device}{$timeStr}{wsa} = 0.01 * (($byteRef->[$base + 2]) + ($byteRef->[$base + 3]<<8));
      $resRef->{$device}{$timeStr}{wsm} = 0.01 * (($byteRef->[$base + 4]) + ($byteRef->[$base + 5]<<8));
      $resRef->{$device}{$timeStr}{wd}  = ($byteRef->[$base + 6]) + ($byteRef->[$base + 7]<<8);      
   
   }

}

##-----------------------------------------------------------------------------
## Unpack data packet 005
##-----------------------------------------------------------------------------
sub call_packetUnpack_005 {
   my ( $byteRef, $resRef, $device ) = @_;
   
   my %time;
   my $packetCount  = 0;
   my $packetLength = $byteRef->[1];

   ## Get the time and calculate the offset for the time in the data buffer
   ## Adjust the buffer for the packet header
   my $dataOffset   = unpack_WindOpMinuteTime($byteRef, \%time);
   $dataOffset += 2;
   
   # printf ("call_packetUnpack_005 Length=%3d ", $packetLength);

   ## From C golden reference
   # outBuffer[0] = readingsIn->tmp & 0x00FF;          // Temperature
   # outBuffer[1] = (readingsIn->tmp & 0xFF00) >> 8;   //
   # outBuffer[2] = readingsIn->press & 0x00FF;        // Pressure
   # outBuffer[3] = (readingsIn->press & 0xFF00) >> 8; //
   # outBuffer[4] = readingsIn->hum & 0x00FF;          // Humidity
   # outBuffer[5] = (readingsIn->hum & 0xFF00) >> 8;   //
   # outBuffer[6] = readingsIn->bv & 0x00FF;           // Battery voltage
   # outBuffer[7] = (readingsIn->bv & 0xFF00) >> 8;    //
      
   my $base = $dataOffset;
   my $timeStr = $time{dt}->ymd('') . $time{dt}->hms('');

   $resRef->{$device}{$timeStr}{tmp}  = 0.1   * (($byteRef->[$base + 0]) + ($byteRef->[$base + 1]<<8));
   $resRef->{$device}{$timeStr}{pres} = 0.01  * (($byteRef->[$base + 2]) + ($byteRef->[$base + 3]<<8));
   $resRef->{$device}{$timeStr}{hum}  = 0.01  * (($byteRef->[$base + 4]) + ($byteRef->[$base + 5]<<8));
   $resRef->{$device}{$timeStr}{bv}   = 0.001 * (($byteRef->[$base + 6]) + ($byteRef->[$base + 7]<<8));      

}

##-----------------------------------------------------------------------------
## Unpack all the packet data
##-----------------------------------------------------------------------------
sub unpackWm868Data {
   my ( $ttnDataRef, $resRef, $device ) = @_;
     
   my $dt1 = DateTime->now( time_zone => 'UTC' );

   # loop over the now decoded data structure
   for (my $i=0; $i < (@$ttnDataRef) ; $i++) {

      printf("---Dev:%3s ID:%6d %s Type:%s\n", $ttnDataRef->[$i]->{device_id}, $i, $ttnDataRef->[$i]->{time}, $ttnDataRef->[$i]->{bytes}[0]);
      my $type = $ttnDataRef->[$i]->{bytes}[0];

      call_packetUnpack_004 ($ttnDataRef->[$i]->{bytes}, $resRef, $device) if($type == 4);
      call_packetUnpack_005 ($ttnDataRef->[$i]->{bytes}, $resRef, $device) if($type == 5);

   }
   
   my $dt2 = DateTime->now( time_zone => 'UTC' ) - $dt1;
   my $length = @$ttnDataRef;
   printf("---Unpack WM868 data packets = %d in %ds\n", $length, $dt2->seconds);

}

##-----------------------------------------------------------------------------
###############################################################################
## General use functions, non windop specific for data fetch and decode
###############################################################################
##-----------------------------------------------------------------------------

##-----------------------------------------------------------------------------
## Functions to build our CURL command line to query the SWAGGER REST API on
## TTN. We run these as *NIX commands at present. We can make a more X platform
## pure perl implementation at some point
##-----------------------------------------------------------------------------
sub retTtndDevices {
  my $cmd = retBaseTtnCommand(shift);
  $cmd .= "devices'";
  return $cmd;
}

sub retTtndQuery {
   my $cfg = shift;
   my $cmd = retBaseTtnCommand($cfg);
   $cmd .= "query/$cfg->{selectDevice}";
   $cmd .= "?last=$cfg->{duration}";
   $cmd .= "'";
   return $cmd;
}

sub retBaseTtnCommand {
  my $cfgRef = shift;

  #----------------------------------------------------------------------------
  # If the config file does not exist, print some help and bail out
  #----------------------------------------------------------------------------
  if (! -e $cfgRef->{ttnkeys}) {
    print ("Keys file $cfgRef->{ttnkeys} does not exist. You need to create and populate with something like
  {
    \"authKey\": \"ttn-account-v.........\",
    \"appPath\": \"https://...........thethingsnetwork.org/..../\"
  }
Log into TTN and run a CURL request from the SWAGGER integration. This will give you the information you need.
These values are simply used to build the CURL command line.
");
    exit();
  }
  
  #----------------------------------------------------------------------------
  # Read in the App keys from the config file
  my $jsonStr = readFileContents($cfgRef->{ttnkeys});
  my $ttnConfig = decode_json( $jsonStr );

  # Not the -s to reduce the curl progress info, otherwise this ends up in the data
  # Build a string of the command we are going to execute.
  my $res = "curl -sX GET --header 'Accept: application/json' --header 'Authorization: key ";
  $res .= $ttnConfig->{authKey};
  $res .= "' '";
  $res .= $ttnConfig->{appPath};
  print "\n$res\n\n" if $cfgRef->{curl};
  return $res;
}

##-----------------------------------------------------------------------------
## This function fetchs the data from the TTN 
##-----------------------------------------------------------------------------
sub queryTtndReturnHashRef {
  my ( $cfgRef ) = @_;

     ## Run the CURL command to get data from a device.
     my $jsonStr = runOsCommandGetOutput(retTtndQuery($cfgRef));
     
     print $jsonStr if $cfgRef->{dump};
     exit() if $cfgRef->{curl};

     ## Convert the JSON string to a PERL data structure
     return decode_json( $jsonStr );

}

##-----------------------------------------------------------------------------
## This function fetchs the data from the TTN 
##-----------------------------------------------------------------------------
sub plotData {
  my ( $outFile ) = @_;
  my $command = "python $Bin/s3_wm_csv_plot.py -c $outFile";
  print("$command\n");
  runOsCommandGetOutput($command);
}

##-----------------------------------------------------------------------------
## Loop over the packet structure and convert from raw base 64 for to 
## integer byte arrays that we can unpack.
## The value that ends up in the "decoded" hash element should match that in
## TTN Application data browser. Again you can use this for debug and checking
## you have recieved the packet as expected.
##-----------------------------------------------------------------------------
sub convertAllRawBase64Packets {
   my ( $ttnDataRef ) = @_;
   
   my $dt1 = DateTime->now( time_zone => 'UTC' );

   my $numberOfPackets = @$ttnDataRef;

   for (my $i=0; $i < $numberOfPackets ; $i++) { 

      ## This line does decode. Lets store the decoded string
      $ttnDataRef->[$i]->{decoded} = base64StrToHex ($ttnDataRef->[$i]->{raw});
       
      ## Now break the decoded string into a Byte array that we can use.
      ## To ease debug we are going to keep this as ASCII hex
      $ttnDataRef->[$i]->{bytes} = []; ## Create the array element so we can pass a reference to it

      ## Do the breakdown. Best to do this here as we are looping over the packets 
      breakHexStringIntoHexByteArray($ttnDataRef->[$i]->{decoded}, $ttnDataRef->[$i]->{bytes});

   }
   my $dt2 = DateTime->now( time_zone => 'UTC' ) - $dt1;

   printf("---Base64 conversion packets = %d in %ds\n", $numberOfPackets, $dt2->seconds);

   return $numberOfPackets;
}

##-----------------------------------------------------------------------------
## Break the decoded string into a Byte array that we can use
##-----------------------------------------------------------------------------
sub breakHexStringIntoHexByteArray {
   my ( $decoded, $bytes ) = @_;
   
   ## Split the string up into an array of single charachters
   my @bArray = split( //, $decoded );
   
   ## get the length of the char array
   my $length = @bArray;
   
   ## Combine them into essentially a Byte array. 0 -> 255
   for (my $byte=0;$byte<$length;$byte+=2) { 
      # ASCII for debug
      # @$bytes[$byte>>1]  =  "$bArray[$byte]" . "$bArray[$byte + 1]"; # debug
      # convert to an integer
      @$bytes[$byte>>1]  =  (hex($bArray[$byte]) << 4) + hex($bArray[$byte + 1]);
   }
}

##-----------------------------------------------------------------------------
# Decode a Base64 string, then convert to a byte hex representation. This 
# should match the format you see on TTN in the data window.
##-----------------------------------------------------------------------------
sub base64StrToHex {
   my @bytes = split //, decode_base64(shift);
   my $str = "";
   foreach (@bytes) {
      $str .= sprintf "%02lx", ord $_;
   }
   return $str;
}

##-----------------------------------------------------------------------------
## returns time in YYYYMMDD_HHMMSS format
##-----------------------------------------------------------------------------
sub getTimeForDataPacket {
  my $dt = DateTime->now( time_zone => 'UTC' );
  my $year = $dt->ymd('');
  return $dt->ymd('') . "_" . $dt->hms('');    # 14!02!29
}

##-----------------------------------------------------------------------------
## write to a file
##-----------------------------------------------------------------------------
sub writeToFile {
  my ( $fileName, $string ) = @_;
  if ( $fileName ne "" ) {
    open( FILE, ">$fileName" ) || die "Can't open $fileName: $!\n";
    print FILE $string;
    close(FILE);
  }
}

##-----------------------------------------------------------------------------
## Append to a file.
##-----------------------------------------------------------------------------
sub appendToFile {
  my ( $fileName, $string ) = @_;

  open( FILE, ">>$fileName" ) || die "Can't open $fileName: $!\n";
  print FILE $string;
  close(FILE);

}

##-----------------------------------------------------------------------------
## Get the contents of a file as a string
##-----------------------------------------------------------------------------
sub readFileContents {
  my ( $fileName ) = @_;
  my $return = "";
  open( FILE, "$fileName" ) || die "Can't open $fileName: $!\n";
  my @temp = <FILE>;
  close(FILE);
  $return = join '', @temp;
  return $return;
}

##-----------------------------------------------------------------------------
# pass back everything recieved from the command
##-----------------------------------------------------------------------------
sub runOsCommandGetOutput {
  my ($command) = @_;

  my $output = runOsCommandSearchOutput( $command, "" );

  return $output;
}

##-----------------------------------------------------------------------------
## The building block for running system commands
## This includes a regexp option to optionally filter each returned line if
## required. This is a *NIX/OXS call only
##-----------------------------------------------------------------------------
sub runOsCommandSearchOutput {
  my ( $command, $searchStr ) = @_;
  my $output = "";

  open( OSCOMMAND, "$command 2>&1 |" ) || die "Failed: $!\n";
  while (<OSCOMMAND>) {
    if (m/$searchStr/) {
      $output .= $_;
    }
  }
  close(OSCOMMAND);

  return $output;
}

