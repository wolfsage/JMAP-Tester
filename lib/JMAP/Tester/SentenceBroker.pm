use strict;
package JMAP::Tester::SentenceBroker;

use Moo;
with 'JMAP::Tester::Role::SentenceBroker';

use JMAP::Tester::Abort 'abort';
use JMAP::Tester::Response::Sentence;
use JMAP::Tester::Response::Paragraph;

sub client_ids_for_items {
  map {; $_->[2] } @{ $_[1] }
}

sub sentence_for_item {
  my ($self, $item) = @_;

  return JMAP::Tester::Response::Sentence->new({
    name      => $item->[0],
    arguments => $item->[1],
    client_id => $item->[2],

    sentence_broker => $self,
  });
}

sub paragraph_for_items {
  my ($self, $items) = @_;

  return JMAP::Tester::Response::Paragraph->new({
    sentences       => [ map {; $self->sentence_for_item($_) } @$items ],
  });
}

sub abort_callback { \&abort }

my $typist;

sub strip_json_types {
  $typist = JSON::Typist->new unless $typist;
  $typist->strip_types($_[1]);
}

no Moo;
1;
