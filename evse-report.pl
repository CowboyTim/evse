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

use JSON;
use POSIX ();

$ENV{TZ} = 'GMT';
POSIX::tzset();

my $base_dir = shift @ARGV or die "Usage: $0 <base_dir>\n";

# loop over the files, collect start/stop transactions
my %start_requests;
my %transactions;
foreach my $file (glob("$base_dir/snoop_blinkcharging_*.log")){
    open(my $fh, '<', $file)
        or do {warn "Could not open '$file': $!\n"; next;};
    while(my $line = <$fh>){
        chomp $line;
        print STDERR "LINE: $line\n" if $ENV{DEBUG};
        if($line =~ m/^(\[.*\])(?:,(.*?),(.*?))?$/){
            my $ocpp_message   = $1;
            unless(length($ocpp_message//'')){
                warn "Empty OCPP message in line: $line\n";
                next;
            }
            my $meter_value    = $2 // '';
            my $consumed_value = $3 // '';
            my $ocpp_message_json = eval {JSON::decode_json($ocpp_message)};
            if($@ or !$ocpp_message_json){
                warn "Failed to decode JSON: $@ in line: $line\n";
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
            $ev->{external_meter_value} = $meter_value     if $meter_value;
            $ev->{consumed_meter_value} = $consumed_value  if $consumed_value;
            $ev->{line}                 = $line;

            # what we do with the message
            if($message_type ==2 and $message_name eq 'StartTransaction'){
                $ev->{epoch_timestamp} = parse_date($message_data->{timestamp});
                if(!defined $ev->{epoch_timestamp}){
                    warn "Failed to parse timestamp '$message_data->{timestamp}' in line: $line\n";
                    next;
                }
                # Store the start transaction data
                $start_requests{$message_id} //= $ocpp_message_json;
            }
            elsif($message_type == 3 and $message_data->{transactionId}){
                $transactions{$message_data->{transactionId}}{start} //= delete $start_requests{$message_id};
            }
            elsif($message_type == 2 and $message_name eq 'StopTransaction'){
                $ev->{epoch_timestamp} = parse_date($message_data->{timestamp});
                if(!defined $ev->{epoch_timestamp}){
                    warn "Failed to parse timestamp '$message_data->{timestamp}' in line: $line\n";
                    next;
                }
                # Update the stop transaction data
                $transactions{$message_data->{transactionId}}{stop} //= $ocpp_message_json;
            }
            elsif($message_type == 2 and $message_name eq 'MeterValues'){
                $ev->{epoch_timestamp} = parse_date($message_data->{meterValue}[0]{timestamp});
                if(!defined $ev->{epoch_timestamp}){
                    warn "Failed to parse timestamp '$message_data->{timestamp}' in line: $line\n";
                    next;
                }
                push @{$transactions{$message_data->{transactionId}}{meter_values}}, $ocpp_message_json;
            }
        } else {
            warn "Line does not match expected format: $line\n";
        }
    }
    close($fh);
}

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

my @tr = (sort {($a->{stop}[4]{epoch_timestamp}//0) <=> ($b->{stop}[4]{epoch_timestamp}//0)}
            grep {$_->{stop} and $_->{start}} values %transactions);

print STDERR JSON->new->canonical->encode(\@tr),"\n" if $ENV{DEBUG};

foreach my $c (@tr){
    my $start = $c->{start}[4];
    my $stop = $c->{stop}[4];
    unless($start and $stop){
        warn "Missing start or stop data in transaction: ",JSON->new->canonical->encode($c),"\n";
        next;
    }
    if(!$stop->{epoch_timestamp}){
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
        if($c->{stop}[3]{meterStop} > $mv_start->[3]{meterValue}[0]{sampledValue}[0]{value}){
            $ch_time += ($stop->{epoch_timestamp} - $mv_start->[4]{epoch_timestamp});
        }
    } else {
        $ch_time = $stop->{epoch_timestamp} - $start->{epoch_timestamp};
    }

    my $ocpp_mv_consumed = ($c->{stop}[3]{meterStop}//0) - ($c->{start}[3]{meterStart}//0);
    printf("%s,%s,%s,%d,%d,%s,%d,%d,%d,%f,%f\n",
        $stop->{file},
        POSIX::strftime("%F %T", gmtime($start->{epoch_timestamp})),
        POSIX::strftime("%F %T", gmtime($stop->{epoch_timestamp})),
        ($stop->{epoch_timestamp} - $start->{epoch_timestamp}),
        $ch_time,
        $c->{stop}[3]{idTag}          // '',
        $c->{start}[3]{meterStart}    // 0,
        $c->{stop}[3]{meterStop}      // 0,
        $ocpp_mv_consumed/1000,
        ($stop->{external_meter_value}//0) - ($start->{external_meter_value} // 0),
        11.2222*($ch_time / 60 / 60),
    );
}
