use strict;
use warnings;

package JMAP::Tester::Test;

sub run_all_tests {
  for my $t (glob 't/lib/JMAP/Tester/Tester/*') {
    require $t;
    $t =~ s|^t/lib/||;
    $t =~ s/\.pm//;
    $t =~ s|/|::|g;

    $t->run_test;
  }
}

1;
