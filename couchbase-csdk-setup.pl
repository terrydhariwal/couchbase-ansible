#!/usr/bin/perl
use strict;
use warnings;

### Repositories:

my $REPOS = {
    RPM => {
        5 => {
            '32bit' => "http://packages.couchbase.com/rpm/5.5/i386",
            '64bit' => "http://packages.couchbase.com/rpm/5.5/x86_64",
        },
        6 => {
            '32bit' => "http://packages.couchbase.com/rpm/6.2/i686",
            '64bit' => "http://packages.couchbase.com/rpm/6.2/x86_64",
        },
        7 => {
            '64bit' => "http://packages.couchbase.com/rpm/7/x86_64"
        }
    },

    DEB => {
        'trusty' => 'deb http://packages.couchbase.com/ubuntu trusty trusty/main',
        'precise' => 'deb http://packages.couchbase.com/ubuntu precise precise/main',
        'lucid' => 'deb http://packages.couchbase.com/ubuntu lucid lucid/main',
        'wheezy' => 'deb http://packages.couchbase.com/ubuntu wheezy wheezy/main'
    }
};

# Figure out the kind of operating system we're on

sub print_supported {
    print STDERR "Supported RPM (RedHat Enterprise Linux, CentOS) platforms:\n";
    foreach my $vnum ( keys %{$REPOS->{RPM}} ) {
        foreach my $arch (keys %{$REPOS->{RPM}->{$vnum}}) {
            print STDERR "  EL $vnum.x - $arch\n";
        }
    }

    print STDERR "\n";
    print STDERR "Supported DEB (Debian, Ubuntu) platforms:\n";
    foreach my $key (keys %{$REPOS->{DEB}}) {
        if ($key eq 'trusty') { $key = "Ubuntu 14.04 LTS (Trusty)" }
        elsif ($key eq 'precise') { $key = "Ubuntu 12.04 LTS (Precise)" }
        elsif ($key eq 'lucid') { $key = "Ubuntu 10.04 LTS (Lucid)" }
        elsif ($key eq 'wheezy') { $key = "Debian 7 (Wheezy: Stable)" }
        print STDERR "  $key\n";
    }

    print STDERR "\n";
    print STDERR "NOTE: You may also try to manually install packages for other\n";
    print STDERR "similar platforms.\n";
}


$| = 1;

my $REPLY;

sub user_terminated {
    print STDERR "Setup will exit because you have requested termination\n";
    exit(1);
}

if ($< != 0) {
    print STDERR "I'm detecting you are not the root user. If I continue, I will\n";
    print STDERR "not be able to make any changes and setup the repositories.\n";
    print STDERR "\n";
    print STDERR "You should run this command using `sudo`; for example, `sudo $0`\n";
    print STDERR "\n";
    print STDERR "Continue? If yes, setup will display the necessary files and modifications\n";
    print STDERR "needed, but not actually make them: [Y/n] ";
    $REPLY = <STDIN>;
    if ($REPLY =~ /n/) {
        user_terminated();
    }
    print STDERR "\n";
}


print STDERR "Will determine the kind of system you are using\n";

my $ARCH = qx(uname -m);
if ($ARCH =~ /64/) {
    $ARCH = '64bit';
} else {
    $ARCH = '32bit';
}

my $RELTYPE;
my $VERSION;


sub get_lsb_field {
    my $name = shift;
    $name = "--$name";
    my $rv = qx(lsb_release $name);
    return (split(' ', $rv))[1];
}

sub prompt_replace_file {
    my $fname = shift;
    if (! -e $fname) {
        return;
    }
    print STDERR "The file '$fname' already exists. Its contents are:\n";
    open my $fp, "<", $fname;
    print STDERR "-- BEGIN --\n";
    foreach my $line (<$fp>) {
        print STDERR $line;
    }
    print STDERR "-- END --\n";
    close($fp);
    print STDERR "\n";
    print STDERR "Should I replace it? [y/N] ";
    $REPLY = <STDIN>;
    unless ($REPLY =~ /y/i) {
        user_terminated();
    }
}
    

if (-e '/etc/redhat-release') {
    # RPM Based system
    $VERSION = get_lsb_field('release');
    if (!$VERSION) {
        # Fallback to parsing redhat-release:
        print STDERR "lsb_release not found. Parsing /etc/redhat-release\n";
        open my $fh, '<', '/etc/redhat-release' or die;
        local $/ = undef;
        $VERSION = <$fh>;
        close $fh;
        ($VERSION) =  ($VERSION =~ /([\d\.]+)/);
    }

    $VERSION =~ s,\..*,,g;
    $RELTYPE = "RPM";

} elsif (-e '/etc/debian_version') {
    # Debian based system
    $VERSION = get_lsb_field('codename');
    $RELTYPE = "DEB";
} else {
    print_supported();
    exit(1);
}

print STDERR "Architecture: $ARCH. Package Type: $RELTYPE. Version: $VERSION\n";
print STDERR "Is this correct? [Y/n]";
$REPLY = <STDIN>;
if ($REPLY =~ /n/) {
    user_terminated();
}
print STDERR "\n";

if ($RELTYPE eq 'DEB') {
    if (!-d '/etc/apt/sources.list.d') {
        print STDERR "Creating /etc/apt/sources.list.d directory.. \n";
        mkdir('/etc/apt/sources.list.d');
        if ($! && $< == 0) {
            die($!);
        }
    }

    my $repofile = '/etc/apt/sources.list.d/couchbase.list';
    prompt_replace_file($repofile);

    my $line = $REPOS->{DEB}->{$VERSION};
    print STDERR "Will insert '$line' into '$repofile'\n";
    my $status = open my $fp, ">", $repofile;
    if ($status) {
        print $fp $line."\n";
        close($fp);
    } elsif ($< == 0) {
        die("$repofile: $!");
    }

    # Now, install the GPG key:
    my $gpgtxt = get_deb_gpg();
    print STDERR "\n";
    print STDERR "Adding GPG Key. Piping GPG key data to `apt-key add -`\n";

    open $fp, "|-", "apt-key", ("add", "-") or die "$!";
    print $fp ($gpgtxt);
    close($fp);

    if ($? >> 8 != 0 && $< == 0) {
        die("Couldn't add apt-key ($?)!\n");
    }

    my $cmd;
    print STDERR "\n";
    print STDERR "Running apt-get -qq update..\n";

    $cmd = "apt-get -qq update";
    if (system($cmd) != 0 && $< == 0) {
        die("Couldn't run $cmd update");
    }

    $cmd = "apt-get -q install ";
    $cmd .= "libcouchbase2-core libcouchbase2-libevent libcouchbase2-bin libcouchbase-dev";

    print STDERR "\n";
    print STDERR "Running: $cmd\n";

    if (system($cmd) != 0 && $< == 0) {
        die("Couldn't install!");
    }



} elsif ($RELTYPE eq 'RPM') {
    # Figure out the architecture and the repository to search for..
    my $repofile = '/etc/yum.repos.d/couchbase.repo';
    my $repoline = $REPOS->{RPM}->{$VERSION}->{$ARCH};
    if (!$repoline) {
        print STDERR "Your platform does not seem to be supported!\n";
        print_supported();
        exit(1);
    }

    prompt_replace_file($repofile);
    my $status = open my $fp, ">", $repofile;
    if ($status) {
        print $fp <<"EOF";
[couchbase]
enabled = 1
name = Couchbase package repository
baseurl = $repoline
gpgcheck = 1
gpgkey = http://packages.couchbase.com/rpm/couchbase-rpm.key
EOF
        close($fp);
    } elsif ($< == 0) {
        die("$repofile: $!");
    }

    # Now, simply do the yum dance:
    my $cmd = "yum install libcouchbase2-libevent libcouchbase-devel libcouchbase2-bin -y";
    print STDERR "\n";
    print STDERR "Running: $cmd\n";
    if (system($cmd) != 0 && $< == 0) {
        die("Couldn't execute Yum!\n");
    }
}

print STDERR "\n";
print STDERR "Will verify your install..\n";
system("cbc version") == 0 or die("Couldn't verify installation!");

sub get_deb_gpg {
    return <<'EOG';
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.12 (GNU/Linux)

mQGiBFBNzokRBADBz7qXEhIMXl7c0JVfdUcrQnfz5KAKS5+XSt0YSHYpXxbrwuwZ
epfJfAgqT3d5/qgHAKrOd0wFLh7h4QqAVA/EqEnBFM8Qsg+ng4CbzS9Z6LnQIbFc
1za+Ax2vxmr6NXEX4vaE4T4jCtexW4QlZ4OoSMxDhiH287Q+nHBg7C9xAwCg2OoR
Wgq03egTMboMtX1OZXZqvUkD/iBl9kY9QjO3n/4/+wKvYwgYJgWm8AL6oCbXM4ik
kNpHIfr46+ijbS8o1vKRjXHlGC/rhYIwqtRpJWvH1CV87ggTIJ+2Gef9WLuQkDUp
RN93S/tW+UjHuebdK406NgBB0qE+f07NNdA3a/VgkSe1KL8XG/K3StaEPvGk/wrB
RRFdA/wK5Z+tdeJwu5cFPpzqcJXnobtPJ31WgCggxLibmzbDMSPzeq7e0eMj0xlo
nnMRTlyKRhzOSy9t29aOJUvrcDhJ0xS6/mu3kPDhw2yK/8q8lfmT4U9XgJiyV47V
ambQmI4CfMaAyru4GY9/Q47pgCFZw8BtD3WwyJdTLlfnJmNzZbQzQ291Y2hiYXNl
IFJlbGVhc2UgS2V5IChSUE0pIDxzdXBwb3J0QGNvdWNoYmFzZS5jb20+iGIEExEC
ACIFAlBNzokCGwMGCwkIBwMCBhUIAgkKCwQWAgMBAh4BAheAAAoJEOkFx3DNQG5i
CT0AnRTuxFGEuzvo+jhNusUnW2wx6lopAJ4oBczMYMozeEGXDwuJSziVCu1LMLkB
DQRQTc6JEAQAj5tEzSDk8WkrWgCO0md7f+8hfFi7zmzRhI7ZmrVUiHHP3rAw44Mm
bMQSOekI2IsMVagt92ZeA0Rxwr7GnVjq9YoR+XoV65QfnmvXpTnvs5PuJNYOYvMY
lVt8EvCG6+U9gRIwb/rKaAeT8kgq4aWEaBxfVHIK/kdUB2bcCL4IB7sAAwUD/Rz7
zREEi0C+PPcWExHHMRCN5s9OI8t5IBEiVW9I2hwRx9tiw73AIRWmdkuALf1P+Rbb
S6lwLp0kUCjV0x8RguIzNRMc8LT4BzH00LM9/64uYPyTwAntM0Rw1k873WmF5tce
agslqoPjSUrxkH+R2qEogTJ5vJZtZaPzyD9maCsfiEkEGBECAAkFAlBNzokCGwwA
CgkQ6QXHcM1AbmLpPQCgjuiiZR2y2QjExW/pYPkJvbVCPYgAoJ1fGrJ6Rtf/KxTb
16HmZRXUSWUA
=u+Fz
-----END PGP PUBLIC KEY BLOCK-----
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.11 (GNU/Linux)

mQENBE9WG3oBCADLn6E7bopPmYVeUY89BLzxi8frjtWIGPxsqQUvIl7NvNrdU+3H
GkrOPH1pYfyY8WWzR7IP8hEBb/nEA7TuVC/mEUDGuyf68WLZI7nJ3Oe/N6cj2I0p
tGM2i9GEVzNtD+7X8B3vdJdLJP6WkAXiznj72BHUEQ83zZFUQfYWN4cgaWg80UHt
+XnHwGxAQoiUFXwdDc6S7jkeC08MIn7z76cfw4lJ+NWjhQjmTP70dGPsCU1qjE+0
hGifBVoI4ZsotPh8JeFX9hwEQfjUTmh6AkX3TugLyLJ4rkW7Lo2nDxowFvMfCYBr
mqIwXsStG9hAvmDzty0XhwU2UUr9Q0/xSmmvABEBAAG0LUNvdWNoYmFzZSBSZWxl
YXNlIEtleSA8c3VwcG9ydEBjb3VjaGJhc2UuY29tPokBOAQTAQIAIgUCT1YbegIb
AwYLCQgHAwIGFQgCCQoLBBYCAwECHgECF4AACgkQo/qmSNkiPtqZvAgAmd4txmq7
q/Gr/vBkZ2/xEFMRu0pGPvN3yPaemDo5A+ctvU6ADPa7oyv3XH1OdA5Dqkxa56f6
qbpHzODlMxJhhimoOzL/QLpH0tF+LIAaOS6xMhUEXvSDrv8y2c5yWgdzvUG8KJ+4
/C0llXg59h2Ir3NVlGsbTpbpLEw6ClU1Q5o7jCGwRip170ntqdNztFYt8C6Uk+vw
65cPdirzxpcGrW/yc91Bto27J9fANUlInZNawGhdf2ppLKCx5rYNnOL48YtphHHc
1XkeayStLTFrLUBwFBZkmjkzeOlJEXxcsC/yOYELmc3jRyMhw4m178fozcS9KKNQ
mB7uCarV6hYwubkBDQRPVht6AQgA7DGK4uStPYhzDdDPv6Pp9Oopv7fTUhbDpKWM
SUzxw5+UXAidPznuIBds2kvYfGhHPp0LxpR2PfafqYCMwqptyFiumVkuJyBWJshO
55P+7IeFKx0W5TmkMZAoCYkB4ixQn0xJYRzOoZ6vCjUiE8e6jpbqhL+s9qW4h+tS
zZOQHssxot+QSbccnU2GyFWbNfvUxIxgP/4fnJJUeGWLIxE6wn8qywiWm3A2nTyV
sbts1RFQ7/Z9vJU+f4NW1/LKvKvb47D8xpOTtCGndyNdbJzIfryBODj0zczqSfcJ
rotmvBMp22wPPwTUUloBVhUUGvGDKNO5scaAzXmMepX2d6eZ7wARAQABiQEfBBgB
AgAJBQJPVht6AhsMAAoJEKP6pkjZIj7av80H/jYckV5QafnlFtNeFxypAfc8+uVG
dym9bGLmx6hd2YPXRMZ5mXrNliNqXjCA/pkV8VKvN8sYa4W+x6hXTmLi5/MiTGky
Q5t5qtxlRWL2zO/fU4L8QgkACysJbNcfPAJb8zkx4GKUZbmzimpXA29I4BrxE+WI
9rgfHddoPXt9x49tl9nloxtszZpm6SDG+gqGi2Da8lcpQx/rHGnfwwfPvVZM1z08
0Kc3wOZd3vSUjt6l0YNAcXwxD8k6q1gSCCEtRXDO/hAsowYJC9lDpkpv4Lh7wq0W
waVofgPSQjccQDBYdfyzK4W8NlJXlbFu8qu54qFOPd7jD8aQCozWE722VJ8=
=y1S/
-----END PGP PUBLIC KEY BLOCK-----
EOG
}