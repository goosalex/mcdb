#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use Time::HiRes qw(time sleep);
use List::Util qw(shuffle);

# Configuration
my $csv_file = 'tunnel_ids.csv';  # File containing the tunnel IDs
my $db_connection_string = 'dbi:Pg:dbname=mydb;host=localhost;port=5432';
my $username = 'username';
my $password = 'password';

# Possible status values
my @status_values = ('UP', 'DOWN', 'DEGRADED', 'UNKNOWN');

# Stats variables
my @execution_times = ();
my $start_time = time();
my $last_stats_time = $start_time;

# Read tunnel IDs from CSV
open(my $fh, '<', $csv_file) or die "Cannot open $csv_file: $!";
my @tunnel_ids;
while (my $line = <$fh>) {
    chomp $line;
    push @tunnel_ids, $line;
}
close $fh;

# Connect to database
my $dbh = DBI->connect($db_connection_string, $username, $password, {
    RaiseError => 1,
    AutoCommit => 0
}) or die "Cannot connect to database: $DBI::errstr";

# Prepare the statement
my $sth = $dbh->prepare_cached(
    "UPDATE vpn.tunnel
    SET
        status=$1,
        status_date=to_timestamp($2),
        rtt=$3,
        loss=$4,
        active=$5,
        octets_per_second_in=$6,
        octets_per_second_out=$7
    WHERE id=$8"
);

# Function to print stats
sub print_stats {
    my $now = time();
    my $elapsed_since_last = $now - $last_stats_time;
    my $total_elapsed = $now - $start_time;

    # Calculate executions in last period
    my $recent_count = 0;
    my $minute_count = 0;

    foreach my $exec_time (@execution_times) {
        if ($now - $exec_time <= 10) {
            $recent_count++;
        }
        if ($now - $exec_time <= 60) {
            $minute_count++;
        }
    }

    # Calculate rates
    my $rate_per_second = $recent_count / 10;
    my $rate_per_minute = $minute_count / min(60, $total_elapsed);

    printf("[%s] Rate: %.2f statements/sec | %.2f statements/min | Total: %d\n",
           scalar(localtime()),
           $rate_per_second,
           $rate_per_minute,
           scalar(@execution_times));

    # Clean up execution times older than 1 minute
    @execution_times = grep { $now - $_ <= 60 } @execution_times;

    $last_stats_time = $now;
}

# Helper function for min value
sub min {
    my ($a, $b) = @_;
    return $a < $b ? $a : $b;
}

# Main execution loop
print "Starting continuous update loop. Press Ctrl+C to exit.\n";

while (1) {
    foreach my $tunnel_id (shuffle @tunnel_ids) {
        # Generate random values
        my $status = $status_values[int(rand(scalar @status_values))];
        my $unix_timestamp = time();
        my $rtt = rand(100);
        my $loss = rand(5);
        my $active = int(rand(2));
        my $octets_in = int(rand(10000));
        my $octets_out = int(rand(10000));

        # Execute update
        $sth->execute(
            $status,
            $unix_timestamp,
            $rtt,
            $loss,
            $active,
            $octets_in,
            $octets_out,
            $tunnel_id
        );

        # Record execution time for stats
        push @execution_times, time();

        # Check if it's time to print stats (every 10 seconds)
        if (time() - $last_stats_time >= 10) {
            # Commit any pending changes
            $dbh->commit();
            print_stats();
        }

        # Commit every 100 records to avoid large transactions
        if (scalar(@execution_times) % 100 == 0) {
            $dbh->commit();
        }

        # Add a small sleep to prevent overwhelming the database
        # Adjust this value based on your requirements
        select(undef, undef, undef, 0.01);
    }

    # Commit any remaining changes before looping again
    $dbh->commit();
}

# This code will never reach here due to infinite loop
$sth->finish();
$dbh->disconnect();