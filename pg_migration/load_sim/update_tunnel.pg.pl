#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use Time::HiRes qw(time);
use List::Util qw(shuffle);

# Configuration
my $csv_file = 'tunnel_ids.csv';  # File containing the tunnel IDs
my $db_connection_string = 'dbi:Pg:dbname=mydb;host=localhost;port=5432';  # PostgreSQL connection string
my $username = 'username';
my $password = 'password';

# Possible status values
my @status_values = ('UP', 'DOWN', 'DEGRADED', 'UNKNOWN');

# Read tunnel IDs from CSV
open(my $fh, '<', $csv_file) or die "Cannot open $csv_file: $!";
my @tunnel_ids;
while (my $line = <$fh>) {
    chomp $line;
    # Assuming the CSV has one ID per line, adjust if your format differs
    push @tunnel_ids, $line;
}
close $fh;

# Connect to database
my $dbh = DBI->connect($db_connection_string, $username, $password, {
    RaiseError => 1,
    AutoCommit => 0
}) or die "Cannot connect to database: $DBI::errstr";

# Prepare the statement - using $1, $2 style parameters for PostgreSQL
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

# Generate randomized data and execute updates
my $counter = 0;
foreach my $tunnel_id (shuffle @tunnel_ids) {
    # Generate random values
    my $status = $status_values[int(rand(scalar @status_values))];
    my $unix_timestamp = time();  # Current time as Unix timestamp
    my $rtt = rand(100);  # Random RTT between 0-100ms
    my $loss = rand(5);   # Random loss percentage between 0-5%
    my $active = int(rand(2));  # 0 or 1 for inactive/active
    my $octets_in = int(rand(10000));  # Random bytes in
    my $octets_out = int(rand(10000)); # Random bytes out

    # Bind parameters and execute - using positional parameters for PostgreSQL
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

    # Print progress
    $counter++;
    print "Updated tunnel ID $tunnel_id ($counter of " . scalar(@tunnel_ids) . ")\n";

    # Commit every 100 records to avoid large transactions
    if ($counter % 100 == 0) {
        $dbh->commit();
        print "Committed batch of 100 records\n";
    }
}

# Final commit for any remaining records
$dbh->commit();
print "All done! Updated " . scalar(@tunnel_ids) . " tunnel records.\n";

# Clean up
$sth->finish();
$dbh->disconnect();