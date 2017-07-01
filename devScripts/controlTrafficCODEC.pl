#!/usr/bin/perl

=head1
  controlTrafficCODEC.pl : Read/Write serial port toolbox

  Copyright (C) 2017  thewindop.com

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program; if not, write to the Free Software Foundation, Inc.,
  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

  Contact: andy\@thewindop.com
  
=cut

use strict;
use Getopt::Long;
use DateTime;
use Data::Dumper;        # Data dumper
use FindBin qw($Bin);    # get path
use feature qw/switch/;

my $helpText = "*" x 80 . "
** genTraffic.pl
" . "*" x 80 . "
Serial port command sequencer. Experiment with command sequences to various
modules. 

    -help|?             : Show help text

    -seq       : [0-9]+ : Sequence file to choose. This is a file mapped
                          to an integer.
    -loop      : int    : Loop the command sequence the number of times given
    -cmd       : string : Command to send. Terminated with a <CR><LF>
    -port      : string : String representing UART port
    -baud      : [0-9]+ : Baud rate
    -module    : string : Load the module file using require. Remove module 
                          head for sub to appear in main namespace

    -readOnly           : only reads the selected port
    -filter    : string : String used as reqular expression to filter 
                          incoming when -read is used
    
    ## To read data from a channel
    genTraffic.pl -read -baud 9600
    
    ## Read and filter using a regular expression
    genTraffic.pl -read -baud 9600 -filter GNRMC

";

###############################################################################
# initialise script, process input
###############################################################################

my $config = returnDefaultSettingsHash();

processCommandLine( $config, $helpText );

findSerialPort( \$config->{port} );

$config->{object} = setupSerialPort($config);

if ( $config->{readOnly} ) {
  justReadAndDisplay( $config->{object}, $config->{filter} );
} else {

  if ( $config->{cmd} ne "" ) {

    # When cmd if given, run the requested command
    logOutBreak();
    logOutNl("** Running command");
    logOutBreak();
    sendCommandGetResp_RN( $config->{object}, $config->{cmd} );
  } else {

    # Otherwise look through the sequences, select one and run it.
    # If a sequence number is given, this will be used, otherise you will
    # need to select a sequence to run at the prompt.
    my $seqFile = findSequences( "$Bin/sequences", $config->{seq} );
    if ( $seqFile ne "" ) {
      logOutBreak();
      logOutNl("** Running commands from $seqFile");
      while ( $config->{loop}-- > 0 ) {
        logOutBreak();
        logOutNl("** Iteration $config->{loop}");
        processExternalCommandsFile( $config->{object}, $seqFile );
      }
    }
  }
}
##-----------------------------------------------------------------------------
## RN command sequences
##-----------------------------------------------------------------------------

sub processExternalCommandsFile {
  my $portRef  = shift;
  my $arrayRef = readFileContentsRetArrayRef(shift);
  foreach my $command (@$arrayRef) {
    if ( $command =~ m/^([^\#]\S+)\s+(.*)/ ) {
      my $type = $1;
      my $arg  = $2;

      given ($type) {
        when (/^sleep$/)                 { sleepCmd($arg); }
        when (/^sendCommandGetResp$/)    { sendCommandGetResp( $config->{object}, $arg ); }
        when (/^sendCommandGetResp_N$/)  { sendCommandGetResp_N( $config->{object}, $arg ); }
        when (/^sendCommandGetResp_RN$/) { sendCommandGetResp_RN( $config->{object}, $arg ); }
        default                          { ; }
      }
    } else {
      logOut($command);
    }
  }
}

##-----------------------------------------------------------------------------
## File IO
##-----------------------------------------------------------------------------
sub readFileContentsRetArrayRef {
  my ($fileName) = @_;
  open( FILE, "$fileName" ) || die "Can't open $fileName: $!\n";
  my @temp = <FILE>;
  close(FILE);
  return \@temp;
}

##-----------------------------------------------------------------------------
## COMMANDS
##-----------------------------------------------------------------------------

##-----------------------------------------------------------------------------
## Sleep wrapper
##-----------------------------------------------------------------------------
sub sleepCmd {
  my $secs = shift;
  logOutNl("Sleeping for $secs");
  sleep($secs);
}

##-----------------------------------------------------------------------------
## serial send string options
##-----------------------------------------------------------------------------
sub sendCommandGetResp_RN {
  return sendCommandGetResp( shift, shift . "\r\n" );    # <CR><LF>
}

sub sendCommandGetResp_N {
  return sendCommandGetResp( shift, shift . "\n" );      # <LF>
}

sub sendCommandGetResp {
  my $comPort       = shift;
  my $output_string = shift;
  logOut("OUT>>>$output_string");
  my $count_out = $comPort->write($output_string);
  my $data      = $comPort->lookfor(255);
  logOutNl("IN <<<$data");
  return $data;
}

sub justReadAndDisplay {
  my $comPort = shift;
  my $regexp  = shift;
  my $data    = "";
  $comPort->are_match("\n");    # possible end strings
  $comPort->lookclear;
  ##
  while (1) {
    $data = $comPort->lookfor();
    logOutNl("IN <<<$data") if ( $data =~ m/$regexp/ );
  }
}

##-----------------------------------------------------------------------------
## Load sequence files
##-----------------------------------------------------------------------------
sub findSequences {
  my ( $directory, $selNo ) = @_;
  my %listHash;
  $listHash{0} = "";    # default 0 is nothing

  opendir my $dir, $directory or die "Cannot open directory: $!";
  my @files = readdir $dir;
  closedir $dir;

  my $counter = 1;
  foreach (@files) {
    if (m/.+\.seq$/) {
      logOutNl("   $counter : $_");
      chomp;
      $listHash{$counter} = "$directory/$_";
      $counter++;
    }
  }

  if ( $selNo == 0 ) {

    # if selNo hasnt been set by the user ask for a valid value
    $selNo = <STDIN>;
    chomp($selNo);
    logOutNl( "Info: " . "You selected $selNo = $listHash{$selNo}" );
  }

  #  print Dumper( \%listHash );#
  return $listHash{$selNo};
}

##-----------------------------------------------------------------------------
##Script helpers
##-----------------------------------------------------------------------------
sub processCommandLine {
  my $cfg = shift;
  $cfg->{seq}      = 0;       # select a sequence to run
  $cfg->{help}     = 0;       # Print help text
  $cfg->{readOnly} = 0;       # Read serial port
  $cfg->{loop}     = 1;       # Number of times to run sequence loop
  $cfg->{module}   = [];      # Additional PERL files read. Subs apper in main namespace
  $cfg->{cmd}      = "";      # command to run
  $cfg->{filter}   = ".+";    #
  GetOptions(
    "seq=s"    => \$cfg->{seq},
    "cmd=s"    => \$cfg->{cmd},
    "port=s"   => \$cfg->{port},
    "baud=s"   => \$cfg->{baud},
    "loop=s"   => \$cfg->{loop},
    "module=s" => \@{$cfg->{module}},
    "filter=s" => \$cfg->{filter},
    "read"     => \$cfg->{readOnly},
    "help|?"   => \$cfg->{help}
  );

  if ( $cfg->{help} ) {
    print shift;
    exit();
  }
  print Dumper($cfg);
  
  foreach my $module (@{$cfg->{module}}) {
    require $module;
#    import $module;
  }
  
  #rn2483_reboot(); # Example for test
  
}

##-----------------------------------------------------------------------------
##Logging
##-----------------------------------------------------------------------------
sub logOutBreak {
  logOutNl( "*" x 80 );
}

sub logOutNl {
  print retTimeStr() . shift . "\n";
}

sub logOut {
  print retTimeStr() . shift . "";
}

##
sub retTimeStr {
  my $dt = DateTime->now;
  my $ts = "[";
  $ts .= sprintf( "%02d", $dt->day );
  $ts .= sprintf( "%02d", $dt->month );
  $ts .= sprintf( "%02d", $dt->year );
  $ts .= " ";
  $ts .= $dt->hms("");
  $ts .= "]";
  return $ts;
}

##-----------------------------------------------------------------------------
## Auto serial port  find
##-----------------------------------------------------------------------------
##
##-----------------------------------------------------------------------------
sub returnDefaultSettingsHash {
  return {
    port    => "",
    baud    => 57600,
    devId   => 101,
    inBytes => 255
  };
}

##-----------------------------------------------------------------------------
## Conditionaly load serial port dependent on OS
##-----------------------------------------------------------------------------
sub setupSerialPort {
  my $cfg = shift;
  my $PortObj;

  #  print Dumper($cfg);

  my $os = $^O;
  $| = 1;

  if ( $os !~ m/Win/ ) {
    require Device::SerialPort;
    $PortObj = Device::SerialPort->new( $cfg->{port} ) || die "Can't open " . $cfg->{port} . ": $^E\n";
  } else {
    require Win32::SerialPort;
    $PortObj = Win32::SerialPort->new( $cfg->{port} ) || die "Can't open " . $cfg->{port} . ": $^E\n";
  }

  $PortObj->databits(8);
  $PortObj->baudrate( $cfg->{baud} );
  $PortObj->parity("none");
  $PortObj->stopbits(1);
  $PortObj->handshake("none");

  $PortObj->write_settings || undef $PortObj;

  if ( $os =~ m/Win/ ) {
    $PortObj->read_interval(100);    # max time between read char (milliseconds)
    $PortObj->write_char_time(5);
    $PortObj->write_const_time(100);
  }
  $PortObj->read_char_time(5);       # avg time between read char
  $PortObj->read_const_time(100);    # total = (avg * bytes) + const
  return $PortObj;
}

###############################################################################
#
###############################################################################
sub findSerialPort {
  my ($portReference) = @_;

  # If the the port is an empty string search for ports
  if ( $$portReference eq "" ) {

    my %SelHash;
    my $counter = 0;

    logOutNl("Searching for serial ports on OS $^O");
    logOutNl("---Select Serial port to use:");
    if ( lc($^O) =~ m/win32/ ) {

      # WINDOWS
      findSerialPort__mswin32( $portReference, 1, \%SelHash, \$counter );
    } elsif ( lc($^O) =~ m/darwin/ ) {

      # OSX
      findSerialPort__osx( $portReference, 1, \%SelHash, \$counter );
    }

    if ( $counter == 0 ) {
      logOutNl( "ERROR : " . "No serial ports are avaiable for server comms, exiting..." );
      exit;
    }

    my $b = <STDIN>;    #does the same thing only puts it into $b;
    chomp($b);
    logOutNl( "Info: " . "You selected $b = $SelHash{$b}" );
    $$portReference = $SelHash{$b};
  }
}

sub findSerialPort__mswin32 {
  my ( $portReference, $enable, $SelHash, $counter ) = @_;
  my $registry;

  # This allow selective load on Win
  require Win32::TieRegistry;

  Win32::TieRegistry->import(
    'ArrayValues' => 1,
    'Delimiter'   => '/',
    'TiedRef'     => \$registry
  );

  my $regkey = 'HKEY_LOCAL_MACHINE/HARDWARE/DEVICEMAP/SERIALCOMM/';
  my $lmachine64 = $registry->Open( $regkey, { 'Access' => Win32::TieRegistry::KEY_READ() } );

  # print Data::Dumper::Dumper( $lmachine64 );

  foreach my $comDeviceName ( sort ( keys( %{$lmachine64} ) ) ) {
    my $comPort = $lmachine64->{$comDeviceName}[0];

    # print "   $comDeviceName $lmachine64->{$comDeviceName}[0]\n";
    $$counter++;
    logOutNl("   $$counter : $comPort");
    $SelHash->{$$counter} = "$comPort";
  }
}

sub findSerialPort__osx {
  my ( $portReference, $enable, $SelHash, $counter ) = @_;

  opendir my $dir, "/dev" or die "Cannot open directory: $!";
  my @files = readdir $dir;
  closedir $dir;

  foreach (@files) {
    if (m/tty\.usb/) {
      $$counter++;
      logOutNl("   $$counter : $_ ");
      chomp;
      $SelHash->{$$counter} = "/dev/$_";
    }
  }
}

