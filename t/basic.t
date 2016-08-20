use strict;
use warnings;

use lib qw(t/lib);

use Test::More;
use JMAP::Tester::Test;

JMAP::Tester::Test->run_all_tests;

done_testing;

1;
