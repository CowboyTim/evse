#!/usr/bin/env perl

use strict; use warnings;

# do we have a file?
my $tcpdump_fn = shift @ARGV;
die usage() unless $tcpdump_fn and -e $tcpdump_fn;

# read in tcpdump streams, in hex
open(my $t_fh, "tshark -r $tcpdump_fn -2 -R 'tcp.stream eq 3 and (websocket || http)' -X lua_script:ws.lua -T fields -e bcencrypt.hex|")
    or die "Error opening tshark: $!\n";
my @p;
while(my $l = <$t_fh>){
    chomp($l);
    next unless length($l);
    $l =~ s/(..)/pack("C", hex($1))/gems;
    push @p, $l;
}

# do we have data?
die usage() unless @p;

#
# Look for a message with 124 bytes, like this:
#
#   [2,"5","StatusNotification",{"connectorId":1,"status":"Available","errorCode":"NoError","timestamp":"2024-06-11T12:49:42Z"}]
#
# See also the OCPP 1.6j standard. Note that this expects the uniqueRequestId to be 1 byte (here: 5).
#
my $msg_nr = 0;
my $msg;
foreach my $data (@p){
    print STDERR $data =~ s/(.)/sprintf("%02X",ord($1))/gesmr, "\n";
    $msg //= $data if length($data) == 124;
    last if $msg;
    $msg_nr++;
}

# find the XOR key
print STDERR "MSG[L:".length($msg).",N:$msg_nr]:$msg\n";
my $s_key8 = get_key($msg, [
    [  0, '['],
    [  1, '2'],
    [  2, ','],
    [  3, '"'],

    [ 24, 'o'],
    [ 25, 'n'],
    [ 26, '"'],
    [ 27, ','],

    [-16, '-'],
    [  9, 't'],
    [ 10, 'a'],
    [-13, 'T'],

    [ 12, 'u'],
    [ 13, 's'],
    [ 14, 'N'],
    [ 15, 'o'],

    [ 16, 't'],
    [ 17, 'i'],
    [ 18, 'f'],
    [ 19, 'i'],
]);

# list as output
foreach my $m (@p){
    pr($m, $s_key8);
}

# print key
print STDERR "S8[".length($s_key8)."]: ".($s_key8 =~ s/./sprintf("%02X",unpack("C", $&))/gesmr).", KEY: ".($s_key8 =~ s/\W/./gsmr)."\n";
print "".($s_key8 =~ s/\W/./gsmr)."\n";
exit;

# FUNCTIONS

sub usage {
    return "usage: $0 <tcpdump file>\n";
}

sub bb {
    my ($w, $n, $what) = @_;
    my $k7;
    my $t = substr($w, $n, 1);
    my $v = $t =~ s/./sprintf("%02X ",ord($&))/gesmr;
    #print "T: $v\n";
    my $r = unpack("C", $t);
    foreach my $k (0 .. 255){
        if(chr($r^$k) eq $what){
            #print "K7: $k(".sprintf("0x%02X",$k)."): ".($r^$k).": ".chr($r^$k)."\n";
            $k7 = $k;
            last
        }
    }
    return $k7
}

sub get_key {
    my ($w, $km) = @_;
    my @kk;
    foreach my $kt (@$km){
        push @kk, bb($w,   $kt->[0], $kt->[1]);
    }
    return pack("C*",@kk);
}

sub pr {
    my ($m, $s_key8) = @_;
    my $fs_key8 = substr(($s_key8) x (int(length($m)/length($s_key8))+1), 0, length($m));
    print STDERR sprintf("%8s: %s\n", "K8",((($fs_key8 =~ s/\W/./gsmr))));
    #print STDERR "H8     : ".((($fs_key8 =~ s/./sprintf("%02X", unpack("C", $&))/gesmr)))."\n";
    print STDERR sprintf("%8s: %s\n", "U8[".length($m)."]", (($m ^ $fs_key8) =~ s/[^A-Za-z0-9_\-\"\{\}\[\],\.:]/./grms));
}

