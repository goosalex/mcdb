#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use Time::HiRes qw(time sleep);
use List::Util qw(shuffle);

# Configuration from environment variables
my $csv_file = $ENV{CSV_FILE} || 'tunnel_ids.csv';
my $db_name = $ENV{DB_NAME} || 'mydb';
my $db_host = $ENV{DB_HOST} || 'localhost';
my $db_port = $ENV{DB_PORT} || '5432';
my $username = $ENV{DB_USER} || 'username';
my $password = $ENV{DB_PASS} || 'password';
my $sleep_interval = $ENV{SLEEP_INTERVAL} || '0.01';

my $db_connection_string = "dbi:Pg:dbname=$db_name;host=$db_host;port=$db_port";

# Possible status values
my @status_values = ('UP', 'DOWN', 'DEGRADED', 'UNKNOWN');

# Stats variables
my @execution_times = ();
my $executions_total = 0;
my $start_time = time();
my $last_stats_time = $start_time;

print "Starting load generator with database: $db_host:$db_port/$db_name\n";

# Read tunnel IDs from CSV
open(my $fh, '<', $csv_file) or die "Cannot open $csv_file: $!";
my @tunnel_ids;
while (my $line = <$fh>) {
    chomp $line;
    push @tunnel_ids, $line;
}
close $fh;

print "Loaded " . scalar(@tunnel_ids) . " tunnel IDs from $csv_file\n";

# Connect to database
print "Connecting to database...\n";
my $dbh = DBI->connect($db_connection_string, $username, $password, {
    RaiseError => 1,
    AutoCommit => 0,
    PrintError => 0
}) or die "Cannot connect to database: $DBI::errstr";

print "Connected successfully to database\n";

# Prepare the statement
my $sth = $dbh->prepare_cached(
    'UPDATE vpn.tunnel
    SET
        status=$1,
        status_date=to_timestamp($2),
        rtt=$3,
        loss=$4,
        active=$5,
        octets_per_second_in=$6,
        octets_per_second_out=$7
    WHERE id=$8'
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
    my $rate_per_minute = $minute_count ;#/ min(60, $total_elapsed);

    printf("[%s] Rate: %.2f statements/sec | %.2f statements/min | Total: %d\n",
           scalar(localtime()),
           $rate_per_second,
           $rate_per_minute,
           $executions_total);

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
        my $status = int(rand(scalar @status_values)); #$status_values[int(rand(scalar @status_values))];
        my $unix_timestamp = time();
        my $rtt = rand(100);
        my $loss = rand(5);
        my $active = int(rand(2));
        my $octets_in = int(rand(10000));
        my $octets_out = int(rand(10000));

        # Execute update
        eval {
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
            $executions_total++;
        };
        if ($@) {
            print "Error executing update: $@\n";
            # Try to reconnect if database connection is lost
            if ($@ =~ /lost connection|connection.*closed/i) {
                print "Reconnecting to database...\n";
                eval {
                    $dbh = DBI->connect($db_connection_string, $username, $password, {
                        RaiseError => 1,
                        AutoCommit => 0
                    });
                    $sth = $dbh->prepare_cached(
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
                };
                if ($@) {
                    print "Reconnection failed: $@\n";
                    sleep(5);  # Wait before retrying
                }
            }
        }

        # Check if it's time to print stats (every 10 seconds)
        if (time() - $last_stats_time >= 10) {
            # Commit any pending changes
            eval { $dbh->commit(); };
            print_stats();
        }

        # Commit every 100 records to avoid large transactions
        if (scalar(@execution_times) % 100 == 0) {
            eval { $dbh->commit(); };
        }

        # Add a small sleep to prevent overwhelming the database
        sleep($sleep_interval);
    }

    # Commit any remaining changes before looping again
    eval { $dbh->commit(); };
}