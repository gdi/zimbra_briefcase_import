#!/usr/bin/perl

use strict;
use Getopt::Long;
use XML::Simple;

# Get script name to ignore it.
my $script_name = $0;
$script_name =~ s/^\.\///g;

# Create folders.
sub create_folders {
	my ($username, $zmmailbox, $upload_path) = @_;
	
	# Get folders that alread exist.
	my @current_folders_list = `$zmmailbox -z -m "$username" getAllFolders`;
	my $current_folders = {};
	chomp @current_folders_list;
	foreach my $c (@current_folders_list) {
		$c =~ s/^\s+\d+\s+[a-z0-9]+\s+\d+\s+\d+\s+//gs;
		if ($c =~ /^\/Briefcase/) {
			$c =~ s/^\/Briefcase\///g;
			$current_folders->{$c} = 1;
		}
	}

	my $cmd = "find \"$upload_path\" -type d";
	my @folders = `$cmd`;
	chomp @folders;
	foreach my $folder (@folders) {
		$folder =~ s/^$upload_path//g;
		$folder =~ s/^\///g;
		if ($folder !~ /^$/) {
			if (! exists($current_folders->{$folder})) {
				$cmd = "$zmmailbox -z -m \"$username\" createFolder -V document \"/Briefcase/$folder\"";
				`$cmd`;
			} else {
				print "WARNING: Folder /Briefcase/$folder already exists!\n";
			}
		}
	}
	return @folders;
}

# Get mime types.
sub get_mime_types {
	my ($mime_types_path) = @_;
	# Open the mime.types file to get extensions and mime types.
	open(TYPES, $mime_types_path) || die "Unable to open mime types file!\n";
	
	my $mime_types = {};
	while (my $line = <TYPES>) {
		$line =~ s/\t/ /g;
		$line =~ s/\s+/ /g;
		$line =~ s/\;//g;
		$line =~ s/\n//;
		if ($line !~ /^#/) {
			my @types = split(/ /, $line);
			my $content_type = @types[0];
			for (my $i = 1; $i < scalar @types; $i++) {
				$mime_types->{@types[$i]} = $content_type;
			}
		}
	}
	return $mime_types;
}


# File uploads.
sub upload_files {
	my ($username, $zmmailbox, $mime_types_path, $upload_path, @folders) = @_;

	my $search_line = "find \"$upload_path\" -type f -and ! -name $script_name";
	my @results = `$search_line`;

	# Get mime types.
	my $mime_types = get_mime_types($mime_types_path);

	# Get a list of existing files.
	my $known_files = {};
	foreach my $folder (@folders) {
		my $item_list = `$zmmailbox -z -m \"$username\" getRestURL \"/Briefcase/$folder?fmt=xml\"`;
		my $xml = XML::Simple->new;
		my $res = $xml->XMLin($item_list);
		if (exists ($res->{'doc'})) {
			my $items = $res->{'doc'};
			if (exists ($items->{'name'})) {
				my $key = "$folder/$items->{name}";
				$known_files->{$key} = 1;
			} else {
				foreach my $file (keys %$items) {
					my $key = "$folder/$file";
					$known_files->{$key} = 1;
				}
			}
		}
	}

	# Upload each of the found files using the content type from mime.types.
	foreach my $file (@results) {
		$file =~ s/^$upload_path//g;
		$file =~ s/^\///g;
		chomp($file);

		my @parts = split(/\./, $file);
		my $ext = @parts[-1];
		$ext =~ tr/A-Z/a-z/;

		my $cmd;
		if (exists $known_files->{$file}) {
			print "ERROR: File $file already exists!\n";
		} else {
			if (exists $mime_types->{$ext}) {
				$cmd = "$zmmailbox -z -m \"$username\" postRestURL --contentType \"$mime_types->{$ext}\" \"/Briefcase/$file\" \"$upload_path/$file\"";
				`$cmd`;
			} else {
				$cmd = "$zmmailbox -z -m \"$username\" postRestURL \"/Briefcase/$file\" \"$upload_path/$file\"";
				`$cmd`;
			}
		}
	}
}

##################### MAIN ########################

my $username = "";
my $zmmailbox = "/opt/zimbra/bin/zmmailbox";
my $mime_types_path = "/opt/zimbra/httpd/conf/mime.types";
my $upload_path = `pwd`;
chomp($upload_path);
my $help;

# Parse ags.
my $res = GetOptions(
	'zmmailbox=s' => \$zmmailbox,
	'username=s' => \$username,
	'mime_types_path=s' => \$mime_types_path,
	'upload_path=s' => \$upload_path,
	'help' => \$help,
);

if ($help || $username eq "" || $username !~ /^[^\s]+\@[a-z0-9\.-]+$/i) {
	print "Usage: ./$script_name <args>\n";
	print " --username\t\tEmail address that will be uploaded to\n";
	print " --zmmailbox\t\tPath to zmmailbox, default:\n";
	print "\t\t\t\t/opt/zimbra/bin/zmmailbox\n";
	print " --mime_types_path\tPath to mime.types file, default:\n";
	print "\t\t\t\t/opt/zimbra/httpd/conf/mime.types\n";
	print " --upload_path\t\tPath to base directory, default:\n";
	print "\t\t\t\tcurrent directory\n\n";
	exit(0);
} elsif (! -f $mime_types_path) {
	print "Need full path to valid mime.types file\n";
	exit(0);
} elsif (! -f $mime_types_path) {
	print "Need full path to zmmailbox bin\n";
	exit(0);
}

my @current_folders = create_folders($username, $zmmailbox, $upload_path);
upload_files($username, $zmmailbox, $mime_types_path, $upload_path, @current_folders);
