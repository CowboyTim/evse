#!/usr/bin/perl

use strict; use warnings;

my @p = (
);

foreach my $data (@p){
    print $data =~ s/(.)/sprintf("%02X",ord($1))/gesmr, "\n";
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
    my ($w) = @_;
    my @kk;
    push @kk, bb($w,   0, "[");
    push @kk, bb($w,   1, "2");
    push @kk, bb($w,   2, ",");
    push @kk, bb($w,   3, '"');

    push @kk, bb($w, -20, "4");
    push @kk, bb($w, -19, "-");
    push @kk, bb($w, -18, "0");
    push @kk, bb($w, -17, "6");

    push @kk, bb($w, -16, "-");
    push @kk, bb($w, -15, "1");
    push @kk, bb($w, -14, "1");
    push @kk, bb($w, -13, "T");

    push @kk, bb($w,  12, "u");
    push @kk, bb($w,  13, "s");
    push @kk, bb($w,  14, "N");
    push @kk, bb($w,  15, "o");

    push @kk, bb($w, 16, "t");
    push @kk, bb($w, 17, "i");
    push @kk, bb($w, 18, "f");
    push @kk, bb($w, 19, "i");

    my $s_key8 = pack("C*",@kk);
    print "S8[".length($s_key8)."]: ".($s_key8 =~ s/./sprintf("%02X",unpack("C", $&))/gesmr).",".($s_key8 =~ s/\W/./gsmr)."\n";
    return $s_key8;
}

my $s_key8 = get_key($p[2]); #OK

sub pr {
    my ($m, $s_key8) = @_;
    my $fs_key8 = substr(($s_key8) x (int(length($m)/length($s_key8))+1), 0, length($m));
    #print "K8: ".((($fs_key8 =~ s/\W/./gsmr)))."\n";
    #print "H8: ".((($fs_key8 =~ s/./sprintf("%02X", unpack("C", $&))/gesmr)))."\n";
    print "U8[".length($m)."]: ".(($m ^ $fs_key8) =~ s/[^A-Za-z0-9_\-\"\{\}\[\],\.:]/./grms)."\n";
}

print "--==OUTPUT==--\n";
pr(substr($p[0],   0, length($p[0])), $s_key8);
pr(substr($p[1], -85, 85), $s_key8);
pr(substr($p[2],   0, length($p[2])), $s_key8);
pr(substr($p[3], -10, 10), $s_key8);
pr(substr($p[4],   0, length($p[4])), $s_key8);
pr(substr($p[5], -10, 10), $s_key8);
pr(substr($p[6],   0, length($p[6])), $s_key8);
pr(substr($p[7], -10, 10), $s_key8);
pr(substr($p[8],   0, length($p[8])), $s_key8);
my $pm = substr($p[9], -10, 10);
print "S[".length($pm)."]:".($pm =~ s/[^A-Za-z0-9_\-\"\{\}\[\],\.:]/./grms)."\n";
print "H[".length($pm)."]:".($pm =~ s/./sprintf("%02X", unpack("C", $&))/grmes)."\n";
pr(substr($p[9], -10, 10), $s_key8);
