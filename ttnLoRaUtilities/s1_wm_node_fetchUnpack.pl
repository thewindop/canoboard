#!/usr/bin/perl

# ============================================================================
# Name        : s1_wm_stream_fetchUnpack.pl
# Author      : Andy Maginnis
# Version     : 1.0.0
# Copyright   : MIT (See below)
# Description : TTN data store fetch and unpack script
#
# Written in PERL as its avaible on most/all *nix/OSX systems. Minimal 
# packages required, you may need JSON.
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
use GIS::Distance;


##-----------------------------------------------------------------------------
## Script start
##-----------------------------------------------------------------------------
my $cfgRef = processCommandLine();

my $noOfPackets = 0 ;
my $dt1 = DateTime->now( time_zone => 'UTC' );

my $ttnDataRef = unPackNodeCsvFile($cfgRef);

# $noOfPackets += convertAllRawBase64Packets($ttnDataRef);

print Dumper $ttnDataRef if($cfgRef->{dump});

my $outFile1 = runWindOpUnpack($ttnDataRef, $cfgRef) if($cfgRef->{runWm});
# my $outFile2 = unpackStreamMetaData($ttnDataRef, $cfgRef) if($cfgRef->{runWm});

# plotData($outFile1) if($cfgRef->{plot});
# plotData($outFile2) if($cfgRef->{rssi});

my $dt2 = DateTime->now( time_zone => 'UTC' ) - $dt1;

printf("---TTN Fetch&Process %d packets in %ds.\n", $noOfPackets, $dt2->seconds);


##-----------------------------------------------------------------------------
## Deal with the command line
##-----------------------------------------------------------------------------
sub processCommandLine {
   my %cfg;

   my $username = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
   $cfg{outdirectory} = "/Users/$username/windop/stream/wmOutData/";
   $cfg{file}         = "";
   $cfg{help}         = 0;
   $cfg{info}         = 0;
   $cfg{quiet}        = 0;
   $cfg{plot}         = 0;
   $cfg{dump}         = 0;
   $cfg{runWm}        = 0;

   GetOptions(
    "outdirectory=s" => \$cfg{outdirectory},# 
    "file=s"         => \$cfg{file},        # 
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

      -outdirectory=s        : Output CSV location, $cfg{outdirectory}
      -runWm                 : Run the WINDOP unpack/CsvGeneration

      -quiet                 : Dont print the data decode statements
      -plot                  : Call the s3 python plot script on the downloaded data.
      -dump                  : Dumps the packet data info & working data Hash. 
      -help                  : Prints this
      -info                  : Prints script dev info
      -curl                  : Show the curl command & exit once run.

## To fetch and process windop data use,


";
      exit();
   }


   if ($cfg{info}) {
print '
  NA.
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

     my $csvFName =  "$cfgRef->{outdirectory}/stream_data_$cfgRef->{selectDevice}";
     $csvFName    .= "_$cfgRef->{duration}";
     $csvFName    .= "_" . getTimeForDataPacket();
     $csvFName    .= ".csv";
     printf("Writing data to $csvFName\n");
     writeToFile( $csvFName, $oFormat);

     return $csvFName;

}


##-----------------------------------------------------------------------------
## Unpack meta data
##-----------------------------------------------------------------------------
sub unpackStreamMetaData {
   my ( $ttnDataRef, $cfgRef ) = @_;
     
   my $dt1 = DateTime->now( time_zone => 'UTC' );
   my $i =0;

   my $oFormat = "time,gws,rssi,snr, freq,\n";

   # loop over the now decoded data structure
   foreach my $key (sort {$a cmp $b} keys (%{$ttnDataRef})) {
      $oFormat .= "$key,";
      $oFormat .= "$ttnDataRef->{$key}{gateway_count},";
      $oFormat .= "$ttnDataRef->{$key}{gateway_info}{0}{rssi},";
      $oFormat .= "$ttnDataRef->{$key}{gateway_info}{0}{snr},";
      $oFormat .= "$ttnDataRef->{$key}{gateway_info}{0}{frequency},";
      if(exists $ttnDataRef->{$key}{gateway_info}{1}) {
         $oFormat .= "$ttnDataRef->{$key}{gateway_info}{1}{rssi},";
         $oFormat .= "$ttnDataRef->{$key}{gateway_info}{1}{snr},";
         $oFormat .= "$ttnDataRef->{$key}{gateway_info}{1}{frequency},";
      }
      $oFormat .= "\n";

   }
   
   my $csvFName =  "$cfgRef->{outdirectory}/stream_metadata_";
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
## Unpack data packet 006
##-----------------------------------------------------------------------------
sub call_packetUnpack_006 {
   my ( $byteRef, $resRef, $device ) = @_;
   
   my %time;
   my $packetCount  = 0;
   my $packetLength = $byteRef->[1];

   ## Get the time and calculate the offset for the time in the data buffer
   ## Adjust the buffer for the packet header
   my $dataOffset   = unpack_WindOpMinuteTime($byteRef, \%time);
   $dataOffset += 2;
   
   printf ("call_packetUnpack_006 Length=%3d ", $packetLength);
      
   my $base = $dataOffset;
   my $timeStr = $time{dt}->ymd('') . $time{dt}->hms('');

   $resRef->{$device}{$timeStr}{tmp}  = 0.01  * (($byteRef->[$base + 0]<<0) + ($byteRef->[$base + 1]<<8) + ($byteRef->[$base + 2]<<16));
   $resRef->{$device}{$timeStr}{pres} = 0.01  * (($byteRef->[$base + 3]<<0) + ($byteRef->[$base + 4]<<8) + ($byteRef->[$base + 5]<<16));
   $resRef->{$device}{$timeStr}{hum}  = 0.01  * (($byteRef->[$base + 6]<<0) + ($byteRef->[$base + 7]<<8));
   $resRef->{$device}{$timeStr}{bv}   = 0.01  * (($byteRef->[$base + 8]) + ($byteRef->[$base + 9]<<8));
   # printf("---------- %x lllll \n ", $resRef->{$device}{$timeStr}{hum});
   # if (($resRef->{$device}{$timeStr}{hum} & 0x8000) == 0x8000) {
      # $resRef->{$device}{$timeStr}{hum} = (~$resRef->{$device}{$timeStr}{hum}) & 0xffff;
   # }     
   # printf("---------- %x lllll \n ", $resRef->{$device}{$timeStr}{hum});

}

##-----------------------------------------------------------------------------
## Unpack data packet 007
##-----------------------------------------------------------------------------
sub processLatLong {
  my $latLong = shift;
  $latLong =~ m/([0-9]+)([0-9]{2}\.[0-9]+)([a-zA-Z]{1})/;
  my $dir     = $3;
  my $seconds = $2;
  my $minutes = $1;
  print "... $latLong [ $seconds === $minutes ]";
  my $result = ($seconds/60) + $minutes;
  $dir = lc($dir);
  $result = 0 - $result if ($dir =~ m/(?:s|w)/);
  print "[ $result ]";
  return $result;
}
sub call_packetUnpack_007 {
   my ( $byteRef, $resRef, $device ) = @_;
   
   my %time;
   my $packetCount  = 0;
   my $packetLength = $byteRef->[1];

   ## Get the time and calculate the offset for the time in the data buffer
   ## Adjust the buffer for the packet header
   my $dataOffset   = unpack_WindOpMinuteTime($byteRef, \%time);
   $dataOffset += 2;
   
   printf ("call_packetUnpack_007 Length=%3d ", $packetLength);
      
   my $base = $dataOffset;
   my $timeStr = $time{dt}->ymd('') . $time{dt}->hms('');


   my $latt = "";
   my $long = "";
   for (my $i = 0; $i < 13; $i++) {
      $latt .= (chr($byteRef->[$base + $i]));
   }
   $latt = processLatLong($latt);

   for (my $i = 13; $i < 126; $i++) {
      $long .= (chr($byteRef->[$base + $i]));
   }
   $long = processLatLong($long);
   my $http = "https://www.google.co.uk/maps/\@$latt,$long,20z";

   my $gis = GIS::Distance->new( );
   my $distance = $gis->distance( 55.8592955,-3.1618687 => $latt,$long );
    
   print (" Distance = " . $distance->meters() . "\n");
   print "load\n$http\n";

   ##system("open $http");


   $resRef->{$device}{$timeStr}{bv}   = 0.001 * (($byteRef->[$base + 26]) + ($byteRef->[$base + 27]<<8));
   # printf("---------- %x lllll \n ", $resRef->{$device}{$timeStr}{hum});
   # if (($resRef->{$device}{$timeStr}{hum} & 0x8000) == 0x8000) {
      # $resRef->{$device}{$timeStr}{hum} = (~$resRef->{$device}{$timeStr}{hum}) & 0xffff;
   # }     
   # printf("---------- %x lllll \n ", $resRef->{$device}{$timeStr}{hum});

}

##-----------------------------------------------------------------------------
## Unpack all the packet data
##-----------------------------------------------------------------------------
sub unpackWm868Data {
   my ( $ttnDataRef, $resRef, $device ) = @_;
     
   my $dt1 = DateTime->now( time_zone => 'UTC' );
   my $i =0;

   # loop over the now decoded data structure
   foreach my $key (sort {$a cmp $b} keys (%{$ttnDataRef})) {
      my $dataRef = $ttnDataRef->{$key};
      my $type = $dataRef->{bytes}[0];

      printf("---Bytes:%3s ID:%6d %s Type:%s\n", $ttnDataRef->{$key}{size}, $i++, $key, $type);

      call_packetUnpack_004 ($dataRef->{bytes}, $resRef, $device) if($type == 4);
      call_packetUnpack_005 ($dataRef->{bytes}, $resRef, $device) if($type == 5);
      call_packetUnpack_006 ($dataRef->{bytes}, $resRef, $device) if($type == 6);
      call_packetUnpack_007 ($dataRef->{bytes}, $resRef, $device) if($type == 7);

   }
   
   my $dt2 = DateTime->now( time_zone => 'UTC' ) - $dt1;

   printf("---Unpack WM868 data packets = %d in %ds\n", $i, $dt2->seconds);

}

##-----------------------------------------------------------------------------
###############################################################################
## General use functions, non windop specific for data fetch and decode
###############################################################################
##-----------------------------------------------------------------------------

##-----------------------------------------------------------------------------
## This function fetchs the data from the TTN 
##-----------------------------------------------------------------------------
sub unPackNodeCsvFile {
  my ( $cfgRef ) = @_;

  my $fileString = readFileContents($cfgRef->{file});
    
  my %results;
  my $count = 3;
  my @keys;
  foreach my $line (split ("\n", $fileString)) {
     # print "$line\n";
     if ($line =~ s/,l,([0-9]+),d,(.*)//) {
           print "$1\n";
           print "$2\n";
           print "$line\n";
           my @bytes = split(m/,/, $2);
           my @data = split(m/,/, $line);
           my $date = $data[0];
           print "@data\n";
           $results{$date}{size} = $1;
           @{$results{$date}{bytes}} = @bytes;


         # if ($count-- > 0) {
  
            # $results{$date}{size} = $1;
            # $results{$date}{json} = $3;
  
            # $results{$date}{json} =~ s/^[\"]//g;
            # $results{$date}{json} =~ s/\"$//;
            # $results{$date}{json} =~ s/\"\"/\"/g;
  
  
         # }
     } else {
        @keys = split (m/,/, lc($line));
        print "@keys\n";
     }
  }

  return \%results;

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

   my $numberOfPackets = keys(%{$ttnDataRef});

   # for (my $i=0; $i < $numberOfPackets ; $i++) { 
   foreach my $key (sort {$a cmp $b} keys (%{$ttnDataRef})) {

      ## This line does decode. Lets store the decoded string
      $ttnDataRef->{$key}{decoded} = base64StrToHex ($ttnDataRef->{$key}{data});
       
      ## Now break the decoded string into a Byte array that we can use.
      ## To ease debug we are going to keep this as ASCII hex
      $ttnDataRef->{$key}{bytes} = []; ## Create the array element so we can pass a reference to it

      ## Do the breakdown. Best to do this here as we are looping over the packets 
      breakHexStringIntoHexByteArray($ttnDataRef->{$key}{decoded}, $ttnDataRef->{$key}{bytes});

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

