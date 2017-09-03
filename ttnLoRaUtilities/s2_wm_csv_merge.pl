#!/usr/bin/perl

# ============================================================================
# Name        : s2_wm_ttn_fetchUnpack.pl
# Author      : Andy Maginnis
# Version     : 1.0.0
# Copyright   : MIT (See below)
# Description : TTN data store fetch and unpack script
#
# Written in PERL as its avaible on most/all *nix/OSX systems. Minimal 
# packages required,.
#
# Merges multiple WM CSV files into a single file.
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

##-----------------------------------------------------------------------------
## Script start
##-----------------------------------------------------------------------------
my @arrayOut;
my %resHash;
my $files=0;
my $dataPoints=0;
my $cfgRef = processCommandLine();

if ( (-e $cfgRef->{outputFile}) & (!$cfgRef->{force})) {
   print "File $cfgRef->{outputFile} exits, cannot overwrite.\n";
   exit();
}

## Get all files of interest, push them onto an array
opendir( DIR, $cfgRef->{inputDir} ) || die "Can't opedir $cfgRef->{inputDir}: $!\n";
my @list = readdir(DIR);
closedir(DIR);
foreach my $f (@list) {
  push @arrayOut, $f if ($f =~ m/$cfgRef->{filter}/);
}

## Loop over each file.
foreach my $csvFile (@arrayOut) {

   ## Get the file contents as an array ref
   my $fileContent = readFileContents("$cfgRef->{inputDir}/$csvFile");

   # get the first line of the CSV which contains the headings. These will be
   # used as HASH keys.
   # The first colunm is always the time which is used as the array key
   my @headings = split (/,/, shift(@$fileContent));
   shift (@headings); # Remove the time header

   ## Variables
   my @lA;
   my $time;

   ## Loop over the headings, shifting the data for each into the appropiate 
   ## HASH key.
   foreach my $line (@$fileContent) {
      chomp $line;              # remove \n
      @lA = split (/,/, $line); # break up the line of data
      $time = shift (@lA);      # remove the reading timestamp
      # Check the timestamp is correct format
      if ($time !~ m/^[0-9]{14}$/) {
         print "Timestamp is not in the correct 14 digit format : $time in file $csvFile\n";
         exit();
      }
      foreach my $name (@headings) {
         ## Put the data in the results hash using the timestamp as a key.
         $resHash{$time}{$name} = shift (@lA);
      }
      $dataPoints++; # counter fo info
   }

   $files++; # counter fo info
}

## Write the CSV output
generateCsvOutput($cfgRef, \%resHash);

my $resLength = keys(%resHash);
print "Processed $files CSV files and $dataPoints datapoints resolved to $resLength\n";

##-----------------------------------------------------------------------------
## Generate a CSV of the data. Manual dump to control the field formatting.
##-----------------------------------------------------------------------------
sub generateCsvOutput {
  my ( $cfgRef, $resHash ) = @_;

     my $oFormat = "time,ws,wsa,wsm,wd,tmp,pres,hum,bv,\n";

     foreach my $time (sort {$a <=> $b} keys ( %{$resHash} )) {
        $oFormat .= "$time,";
        $oFormat .= (exists $resHash->{$time}{ws})   ? "$resHash->{$time}{ws},"   : ",";
        $oFormat .= (exists $resHash->{$time}{wsa})  ? "$resHash->{$time}{wsa},"  : ",";
        $oFormat .= (exists $resHash->{$time}{wsm})  ? "$resHash->{$time}{wsm},"  : ",";
        $oFormat .= (exists $resHash->{$time}{wd})   ? "$resHash->{$time}{wd},"   : ",";
        $oFormat .= (exists $resHash->{$time}{tmp})  ? "$resHash->{$time}{tmp},"  : ",";
        $oFormat .= (exists $resHash->{$time}{pres}) ? "$resHash->{$time}{pres}," : ",";
        $oFormat .= (exists $resHash->{$time}{hum})  ? "$resHash->{$time}{hum},"  : ",";
        $oFormat .= (exists $resHash->{$time}{bv})   ? "$resHash->{$time}{bv},"   : ",";
        $oFormat .= "\n";
     }

     # print ("$oFormat\n");

     # if ( !-e $cfgRef->{outdirectory} ) {
     #    make_path($cfgRef->{outdirectory});
     # }

     my $csvFName =  "$cfgRef->{outputFile}";
     writeToFile( $csvFName, $oFormat);

}

##-----------------------------------------------------------------------------
## Deal with the command line
##-----------------------------------------------------------------------------
sub processCommandLine {
   my %cfg;

   my $username = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
   $cfg{inputDir}     = "./";
   $cfg{outputFile}   = "./combinedCsv.csv";
   $cfg{filter}       = ".*";
   $cfg{force}        = 0;
   $cfg{help}         = 0;
   $cfg{info}         = 0;
   $cfg{dump}         = 0;

   GetOptions(
    "inputDir=s"     => \$cfg{inputDir},   # List what divices are avaiable 
    "outputFile=s"   => \$cfg{outputFile}, # 1h, 2d etc. As defined by Swagger
    "filter=s"       => \$cfg{filter},     #  
    "force"          => \$cfg{force},       #  
    "help"           => \$cfg{help},       #  
    "dump"           => \$cfg{dump}        #  
   );

   if ($cfg{help}) {
      print "
   Merge WINDOP csv data sets

      -inputDir=s            : Directory with CSV files to merge
      -outputFile=s          : Output filename
      -filter=s              : Regular expression to filter input filenames
      -force                 : Force overwrite of output file if it exists

      -dump                  : Dumps the packet data info & working data Hash. 
      -help                  : Prints this

";
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
###############################################################################
## General use functions, non windop specific for data fetch and decode
###############################################################################
##-----------------------------------------------------------------------------

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
## Get the contents of a file as a string
##-----------------------------------------------------------------------------
sub readFileContents {
  my ( $fileName ) = @_;
  my $return = "";
  open( FILE, "$fileName" ) || die "Can't open $fileName: $!\n";
  my @temp = <FILE>;
  close(FILE);
  return  \@temp;
}

