#!/usr/bin/perl

use strict; use warnings;

# read in files structured like this:
#   blinkcharging/snoop_blinkcharging_2025-03-17.log
#   blinkcharging/snoop_blinkcharging_2025-03-18.log
#
# with OCPP 1.6j messages like this:
#   [,,](,extra data)
# 
# E.g.:
#   [2,"82","StartTransaction",{"connectorId":1,"idTag":"B4946B8C","timestamp":"2025-06-03T07:33:23Z","meterStart":6514787}],1969.62890625,0
#   [3,"82",{"transactionId":642,"idTagInfo":{"status":"Accepted","parentIdTag":"B4946B8C","expiryDate":"2025-06-04T09:33:49.123Z"}}]
#   [2,"111","MeterValues",{"connectorId":1,"transactionId":643,"meterValue":[{"timestamp":"2025-06-03T11:19:18Z","sampledValue":[{"value":"6515723"}]}]}],1972.47192382812,1972.47192382812
#   [3,"111",{}]
#   [2,"105","StopTransaction",{"transactionId":642,"idTag":"B4946B8C","timestamp":"2025-06-03T10:20:09Z","meterStop":6514998}],1970.27294921875,1970.27294921875
#   [3,"105",{}]
#
# Where:
#    0: is a ACTION: 2 is send, 3 is received (acknowledge send).
#    1: is a MESSAGE ID, e.g. 82, 111, 105
#    2: is a MESSAGE NAME, e.g. StartTransaction, MeterValues, StopTransaction. However, certain messages are just a JSON object for ACK.
#    3: is a JSON object with the message data.
#
# Multiple same MESSAGE ID's will be logged, but they are the same message, just logger wrongly multiple times.
# The extra data is not always present, just with StartTransaction, MeterValues, and StopTransaction messages, and is 2 numbers:
#    4: metervalue at that time
#    5: calculated difference StartTransaction to StopTransaction of metervalue

# we give a base dir as option to the script

BEGIN {
    unshift @INC, $0 =~ s/\/[^\/]*$//gr;
}

use JSON::XS;
use POSIX ();

BEGIN {
    $0 = "evse:ocpp_report";
}

$ENV{TZ} = 'GMT';
POSIX::tzset();

my $base_dir = shift @ARGV or die "Usage: $0 <base_dir>\n";
opendir(my $base_dir_fh, $base_dir)
    or die "Problem opening $base_dir: $!\n";

# loop over the files, collect start/stop transactions
my %start_requests;
my %transactions;
foreach my $f (readdir($base_dir_fh)){
    next unless $f =~ m/^snoop_blinkcharging_.*\.log$/;
    my $file = "$base_dir/$f";
    open(my $fh, '<', $file)
        or do {warn "Could not open '$file': $!\n"; next;};
    my $base_fn = $file =~ s/.*\/+//gr;
    my $lf_info = "[$base_fn] ";
    while(my $line = <$fh>){
        chomp $line;
        print STDERR "LINE? $line\n" if $ENV{DEBUG};
        next if $line =~ m/(Heartbeat|currentTime)/; # faster
        print STDERR "LINE: $line\n" if $ENV{DEBUG};
        if($line =~ m/^(\[.*\])(?:,(.*?)(?:,(:?.*?))?)?$/){
            my $ocpp_message = $1;
            unless(length($ocpp_message//'')){
                warn "${lf_info}Empty OCPP message in line: $line\n";
                next;
            }
            my $meter_value    = $2 // '';
            my $ocpp_message_json = eval {JSON::XS::decode_json($ocpp_message)};
            if($@ or !$ocpp_message_json){
                warn "${lf_info}Failed to decode JSON: $@ in line: $line\n";
                next;
            }

            # shorthands
            my $message_type = $ocpp_message_json->[0];
            my $message_id   = $ocpp_message_json->[1];
            my $message_name = $ocpp_message_json->[2];
            my $message_data = $ocpp_message_json->[3] // $message_name;

            # our extra info
            my $ev = $ocpp_message_json->[4] = {};
            $ev->{file}                 = $file =~ s/\Q$base_dir\///gr;
            $ev->{external_meter_value} = $meter_value if $meter_value;
            $ev->{line}                 = $line;

            my $tr_id = $message_data->{transactionId} // '';
            my $ms_ts = $message_data->{timestamp} // '';

            # what we do with the message
            if($message_type ==2 and $message_name eq 'StartTransaction'){
                $ev->{epoch_timestamp} = parse_date($ms_ts);
                if(!defined $ev->{epoch_timestamp}){
                    warn "${lf_info}Failed to parse timestamp '$ms_ts' in line: $line\n";
                    next;
                }
                # Store the start transaction data
                $start_requests{$message_id} //= $ocpp_message_json;
            }
            elsif($message_type == 3 and $tr_id){
                $transactions{$tr_id}{start} //= delete $start_requests{$message_id};
            }
            elsif($message_type == 2 and $message_name eq 'StopTransaction'){
                $ev->{epoch_timestamp} = parse_date($ms_ts);
                if(!defined $ev->{epoch_timestamp}){
                    warn "${lf_info}Failed to parse timestamp '$ms_ts' in line: $line\n";
                    next;
                }
                # Update the stop transaction data
                $transactions{$tr_id}{stop} //= $ocpp_message_json;
            }
            elsif($message_type == 2 and $message_name eq 'MeterValues'){
                my $mv_ts = $message_data->{meterValue}[0]{timestamp} // '';
                $ev->{epoch_timestamp} = parse_date($mv_ts);
                if(!defined $ev->{epoch_timestamp}){
                    warn "${lf_info}Failed to parse timestamp '$mv_ts' in line: $line\n";
                    next;
                }
                push @{$transactions{$tr_id}{meter_values}}, $ocpp_message_json;
            }
        } else {
            warn "${lf_info}Line does not match expected format: $line\n";
        }
    }
    close($fh);
}
closedir($base_dir_fh);

sub parse_date {
    # Convert the date string to epoch time
    my $date_str = shift;
    return unless length($date_str//"");
    if($date_str =~ m/\d+-\d+-\d+T\d+:\d+:\d+Z/){
        my ($year, $month, $day, $hour, $min, $sec) = $date_str =~ m/(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)Z/;
        return POSIX::mktime($sec, $min, $hour, $day, $month-1, $year-1900);
    }
    return;
}

my @tr = (sort {($a->{start}[4]{epoch_timestamp}//0) <=> ($b->{start}[4]{epoch_timestamp}//0)}
            grep {$_->{start}} values %transactions);

print STDERR JSON->new->canonical->encode(\@tr),"\n" if $ENV{DEBUG};

foreach my $c (@tr){
    my $start = $c->{start}[4];
    unless($start){
        warn "Missing start data in transaction: ",JSON->new->canonical->encode($c),"\n";
        next;
    }
    my $stop = $c->{stop}[4];
    if($stop and !$stop->{epoch_timestamp}){
        warn "Missing stop timestamp in transaction: ",JSON->new->canonical->pretty->encode($c),"\n";
        next;
    }

    my $ch_time = 0;
    my @mv = sort {$a->[4]{epoch_timestamp} <=> $b->[4]{epoch_timestamp}} @{$c->{meter_values} // []};
    if(@mv){
        my $mv_start = $mv[0]   // {};
        my $mv_stop  = $mv[-1]  // {};
        if(!$mv_start->[4]{epoch_timestamp} or !$mv_stop->[4]{epoch_timestamp}){
            warn "$c->{start}[4]{line} has problems with MeterValues\n";
            next;
        }
        # now sorted, compare, and if a change in meterValue, add to charge time
        $ch_time += ($mv_start->[4]{epoch_timestamp} - $start->{epoch_timestamp});
        foreach my $m_c (@mv){
            my $mv_c = $m_c->[3]{meterValue}[0]{sampledValue}[0]{value} // 0;
            if($mv_c > $mv_start->[3]{meterValue}[0]{sampledValue}[0]{value}){
                $ch_time += ($m_c->[4]{epoch_timestamp} - $mv_start->[4]{epoch_timestamp});
                $mv_start = $m_c;
            }
        }
        if($stop and $c->{stop}[3]{meterStop} > $mv_start->[3]{meterValue}[0]{sampledValue}[0]{value}){
            $ch_time += ($stop->{epoch_timestamp} - $mv_start->[4]{epoch_timestamp});
        }
    } else {
        $ch_time = ($stop->{epoch_timestamp}//0) - $start->{epoch_timestamp};
    }

    my $ocpp_mv_consumed = ($c->{stop}[3]{meterStop}//$mv[-1][3]{meterValue}[0]{sampledValue}[0]{value}//0)
        - ($c->{start}[3]{meterStart}//0);
    $ocpp_mv_consumed //= 0;
    $ocpp_mv_consumed  /= 1000;
    my $external_mv_consumed =
        ($stop->{external_meter_value}
        //($mv[-1]//[])->[4]{external_meter_value}
        //0)
        - ($start->{external_meter_value}//0);
    $external_mv_consumed //= 0;
    my $stop_time = $stop->{epoch_timestamp} // 0;
    printf("%s,%s,%s,%d,%d,%s,%d,%d,%d,%f,%f\n",
        $start->{file},
        POSIX::strftime("%F %T", gmtime($start->{epoch_timestamp})),
        POSIX::strftime("%F %T", gmtime($stop_time)),
        $stop_time?($stop_time - $start->{epoch_timestamp}):0,
        $ch_time,
        $c->{start}[3]{idTag}         // '',
        $c->{start}[3]{meterStart}    // 0,
        $c->{stop}[3]{meterStop}      // 0,
        $ocpp_mv_consumed,
        $external_mv_consumed,
        ($external_mv_consumed?$external_mv_consumed: $ocpp_mv_consumed)/$ocpp_mv_consumed,
    );
}
