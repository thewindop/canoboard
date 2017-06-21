# DOnt actually need to define as package to use.... sweet!
#package LoRa_RN2483_commands;
#use strict;
#use warnings;

sub rn2483_reboot {
  my $sub_name = ( caller(0) )[3];
  print "$sub_name\n";
}

1;
