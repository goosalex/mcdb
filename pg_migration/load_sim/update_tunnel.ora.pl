#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use Time::HiRes qw(time);
use List::Util qw(shuffle);

# Configuration
my $csv_file = 'tunnel_ids.csv';  # File containing the tunnel IDs
my $db_connection_string = 'dbi:Oracle:hostname/service';  # Update with your actual connection details
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

# Prepare the statement
my $sth = $dbh->prepare_cached(
    "UPDATE vpn.tunnel
    SET
        status=:STATUS,
        status_date=TIMESTAMP '1970-01-01 00:00:00 UTC'+ NUMTODSINTERVAL(:UNIX_TIMESTAMP, 'SECOND'),
        rtt=:RTT,
        loss=:LOSS,
        active=:ACTIVE,
        octets_per_second_in=:OCTETS_IN,
        octets_per_second_out=:OCTETS_OUT
    WHERE id=:TUNNEL_ID"
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

    # Bind parameters and execute
    $sth->bind_param(':STATUS', $status);
    $sth->bind_param(':UNIX_TIMESTAMP', $unix_timestamp);
    $sth->bind_param(':RTT', $rtt);
    $sth->bind_param(':LOSS', $loss);
    $sth->bind_param(':ACTIVE', $active);
    $sth->bind_param(':OCTETS_IN', $octets_in);
    $sth->bind_param(':OCTETS_OUT', $octets_out);
    $sth->bind_param(':TUNNEL_ID', $tunnel_id);

    $sth->execute();

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