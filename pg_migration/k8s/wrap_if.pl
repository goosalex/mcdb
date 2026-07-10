use strict;
use warnings;
use File::Spec;


my $config_dir = '/job-config';
my $data_dir = '/data/data_output';
my $names_file = $config_dir.'/schema.names';
my $dirs_file  =  $config_dir.'/schema.dirs';

sub extract_table_name {
    my ($include_line, $schema_name) = @_;

    # Extract the path from the \i statement
    my ($path) = $include_line =~ /\\i\s+'([^']+)'/;
    return undef unless $path;

    # Convert to lowercase
    my $table_name = lc($path);

    # Remove everything before and including the last slash
    $table_name =~ s/.*\///;

    # Remove the schema name suffix and .txt extension
    $table_name =~ s/_\Q$schema_name\E\.txt$//i;

    return $table_name;
}

my $table_check_sql = <<'END_SQL';
CREATE OR REPLACE FUNCTION public.table_exists(schema_name_arg text, table_name_arg text)
    RETURNS bool AS
$$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = schema_name_arg
          AND table_name = table_name_arg
    ) THEN
        return false;
    ELSE
        return true;
    END IF;
END;
$$ LANGUAGE plpgsql;
END_SQL

open my $names_fh, '<', $names_file or die "Cannot open $names_file: $!";
open my $dirs_fh,  '<', $dirs_file  or die "Cannot open $dirs_file: $!";

while (my $schema_name = <$names_fh>) {
    chomp $schema_name;
    my $schema_dir = <$dirs_fh>;
    chomp $schema_dir;
    next unless $schema_name && $schema_dir;

    my $control_file = "$data_dir/$schema_dir/$schema_name.txt";
    # Read the control file
    open my $in_fh, '<', $control_file or die "Cannot open $control_file: $!";
    my @lines = <$in_fh>;
    close $in_fh;
    my $output_file = "$data_dir/$schema_dir/$schema_name.psql";
    open my $out_fh, '>', $output_file or die "Cannot write $output_file: $!";
    print $out_fh $table_check_sql;
    print $out_fh "\n";
    # Process each line
    foreach my $line (@lines) {
        if ($line =~ /^SET /) {
                print $out_fh $line; # Settings lines, keep them
                next;
            }
        if ($line =~ /^\\i\s+'([^']+)'/) {
            my $inc_path = $1;

            # Only process included files (simulate: line starts with \i)
            # Here, we treat every .txt file as an included file
            # Check if file exists before attempting to open
            if (!-e $inc_path) {
                warn "WARNING: Included file '$inc_path' does not exist, skipping\n";
                next;
            }
            my $include_line = $line;
            my $table_name = extract_table_name($include_line, $schema_name);
        my $table_check_sql = <<"END_SQL";
SELECT table_exists('$schema_name', '$table_name') as v_exists
\\gset
\\if :v_exists
BEGIN;
\\i '$inc_path'
COMMIT;
\\else
    \\echo Table '$table_name' does not exist in schema '$schema_name', skipping include of '$inc_path'
\\endif
END_SQL
        print $out_fh $table_check_sql;
        print $out_fh "\n";
        } else {
            # print $out_fh $line; # Other lines, don't keep them
        }

    }
    close $out_fh;

}