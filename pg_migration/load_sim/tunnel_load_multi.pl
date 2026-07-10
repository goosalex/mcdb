#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use Time::HiRes qw(time sleep);
use List::Util qw(shuffle);
use threads;
use threads::shared;
use Thread::Queue;
use Thread::Semaphore;

# Configuration from environment variables
my $csv_file = $ENV{CSV_FILE} || 'tunnel_ids.csv';
my $db_name = $ENV{DB_NAME} || 'mydb';
my $db_host = $ENV{DB_HOST} || 'localhost';
my $db_port = $ENV{DB_PORT} || '5432';
my $username = $ENV{DB_USER} || 'username';
my $password = $ENV{DB_PASS} || 'password';
my $sleep_interval = $ENV{SLEEP_INTERVAL} || '0.01';
my $num_threads = $ENV{NUM_THREADS} || 20;  # Number of parallel threads

my $db_connection_string = "dbi:Pg:dbname=$db_name;host=$db_host;port=$db_port";

# Possible status values
my @status_values = ('UP', 'DOWN', 'DEGRADED', 'UNKNOWN');

# Stats variables shared between threads
my $executions_total :shared = 0;
my @execution_times :shared;
my $start_time :shared = time();
my $last_stats_time :shared = $start_time;
my $stats_lock = Thread::Semaphore->new(1);

print "Starting load generator with database: $db_host:$db_port/$db_name using $num_threads threads\n";

# Read tunnel IDs from CSV
open(my $fh, '<', $csv_file) or die "Cannot open $csv_file: $!";
my @tunnel_ids;
while (my $line = <$fh>) {
    chomp $line;
    push @tunnel_ids, $line;
}
close $fh;

print "Loaded " . scalar(@tunnel_ids) . " tunnel IDs from $csv_file\n";

# Function to print stats
sub print_stats {
    my $now = time();
    my $elapsed_since_last = $now - $last_stats_time;
    my $total_elapsed = $now - $start_time;

    # Calculate executions in last period
    my $recent_count = 0;
    my $minute_count = 0;

    $stats_lock->down();
    foreach my $exec_time (@execution_times) {
        if ($now - $exec_time <= 10) {
            $recent_count++;
        }
        if ($now - $exec_time <= 60) {
            $minute_count++;
        }
    }

    # Clean up execution times older than 1 minute
    @execution_times = grep { $now - $_ <= 60 } @execution_times;
    $stats_lock->up();

    # Calculate rates
    my $rate_per_second = $recent_count / 10;
    my $rate_per_minute = $minute_count;

    printf("[%s] Rate: %.2f statements/sec | %.2f statements/min | Total: %d | Threads: %d\n",
           scalar(localtime()),
           $rate_per_second,
           $rate_per_minute,
           $executions_total,
           $num_threads);

    $last_stats_time = $now;
}

# Helper function for min value
sub min {
    my ($a, $b) = @_;
    return $a < $b ? $a : $b;
}

# Worker thread function
sub worker_thread {
    my ($thread_id, $ids_ref) = @_;
    my @thread_ids = @$ids_ref;

    print "Thread $thread_id starting with " . scalar(@thread_ids) . " IDs\n";

    # Connect to database
    my $dbh = DBI->connect($db_connection_string, $username, $password, {
        RaiseError => 1,
        AutoCommit => 0,
        PrintError => 0
    }) or die "Thread $thread_id: Cannot connect to database: $DBI::errstr";

    # Prepare the statement
    my $sth = $dbh->prepare_cached(
        'UPDATE vpn.tunnel2
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

    # Main execution loop for this thread
    while (1) {
        foreach my $tunnel_id (shuffle @thread_ids) {
            # Generate random values
            my $status = int(rand(scalar @status_values));
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
                $stats_lock->down();
                push @execution_times, time();
                $executions_total++;
                $stats_lock->up();
            };

            if ($@) {
                print "Thread $thread_id error executing update: $@\n";
                # Try to reconnect if database connection is lost
                if ($@ =~ /lost connection|connection.*closed/i) {
                    print "Thread $thread_id reconnecting to database...\n";
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
                        print "Thread $thread_id reconnection failed: $@\n";
                        sleep(5);  # Wait before retrying
                    }
                }
            }

            # Commit every 100 records to avoid large transactions
            if ($executions_total % 100 == 0) {
                eval { $dbh->commit(); };
            }

            # Add a small sleep to prevent overwhelming the database
            sleep($sleep_interval);
        }

        # Commit any remaining changes before looping again
        eval { $dbh->commit(); };
    }
}

# Divide tunnel IDs among threads
my $ids_per_thread = int(scalar(@tunnel_ids) / $num_threads) + 1;
my @threads;

# Start worker threads
for my $i (0..$num_threads-1) {
    my $start_idx = $i * $ids_per_thread;
    my $end_idx = ($i + 1) * $ids_per_thread - 1;
    $end_idx = $#tunnel_ids if $end_idx > $#tunnel_ids;

    my @thread_ids = @tunnel_ids[$start_idx..$end_idx];

    # Skip creating thread if no IDs assigned
    next unless @thread_ids;

    push @threads, threads->create(\&worker_thread, $i, \@thread_ids);
}

print "Started $num_threads worker threads\n";

# Stats reporting thread
while (1) {
    sleep(10);  # Print stats every 10 seconds
    print_stats();
}

# This will never be reached due to infinite loop
foreach my $thread (@threads) {
    $thread->join();
}