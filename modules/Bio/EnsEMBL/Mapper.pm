

#
# Ensembl module for Bio::EnsEMBL::Mapper
#
# Written by Ewan Birney <birney@ebi.ac.uk>
#
# Copyright GRL/EBI
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Mapper

=head1 SYNOPSIS

  # add a coodinate mapping - supply two pairs or coordinates
  $map->add_map_coordinates(
    $contig_id, $contig_start, $contig_end, $contig_ori,
    $chr_name, chr_start, $chr_end
  );

  # map from one coordinate system to another
  my @coordlist = $mapper->map_coordinates(627012, 2, 5, -1, "rawcontig");

=head1 DESCRIPTION

Generic mapper to provide coordinate transforms between two
disjoint coordinate systems. This mapper is intended to be
'context neutral' - in that it does not contain any code
relating to any particular coordinate system. This is
provided in, for example, Bio::EnsEMBL::AssemblyMapper.

=head1 AUTHOR - Ewan Birney

This module is part of the Ensembl project http://www.ensembl.org

Post general queries to B<ensembl-dev@ebi.ac.uk>

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::Mapper;
use vars qw(@ISA);
use strict;

# Object preamble - inherits from Bio::Root::RootI

use Bio::Root::RootI;
use Bio::EnsEMBL::Mapper::Pair;
use Bio::EnsEMBL::Mapper::Unit;
use Bio::EnsEMBL::Mapper::Coordinate;
use Bio::EnsEMBL::Mapper::Gap;

@ISA = qw(Bio::Root::RootI);


sub new {
  my($class,@args) = @_;

  my $from = shift @args;
  my $to   = shift @args;

  my $self = {};
  bless $self,$class;

  if( !defined $to ) {
      $self->throw("Must supply from and to tags");
  }

  $self->{'_pair_hash_to'} = {};
  $self->{'_pair_hash_from'} = {};

  $self->to($to);
  $self->from($from);

# set stuff in self from @args
  return $self;
}


=head2 map_coordinates

    Arg  1      int $id
                id of 'source' sequence
    Arg  2      int $start
                start coordinate of 'source' sequence
    Arg  3      int $end
                end coordinate of 'source' sequence
    Arg  4      int $strand
                raw contig orientation (+/- 1)
    Arg  5      int $type
                nature of transform - gives the type of
                coordinates to be transformed *from*
    Function    generic map method
    Returntype  array of Bio::EnsEMBL::Mapper::Coordinate
                and/or   Bio::EnsEMBL::Mapper::Gap
    Exceptions  none
    Caller      Bio::EnsEMBL::Mapper

=cut

sub map_coordinates{
   my ($self, $id, $start, $end, $strand, $type) = @_;

   if( !defined $type ) {
       $self->throw("Must start,end,strand,id,type as coordinates");
   }

   my $self_func;
   my $target_func;
   my $hash;

   if( $type eq $self->to ) {
       $self_func = \&Bio::EnsEMBL::Mapper::Pair::to;
       $target_func = \&Bio::EnsEMBL::Mapper::Pair::from;
       $hash  = $self->{'_pair_hash_to'};
   } elsif ( $type eq $self->from ) {
       $self_func = \&Bio::EnsEMBL::Mapper::Pair::from;
       $target_func = \&Bio::EnsEMBL::Mapper::Pair::to;
       $hash  = $self->{'_pair_hash_from'};
   } else {
       $self->throw("Type $type is neither to or from coordinate systems");
   }

   if( $self->_is_sorted == 0 ) {
       $self->_sort();
   }

   if( !defined $hash->{$id} ) {
       # one big gap!
       my $gap = Bio::EnsEMBL::Mapper::Gap->new();
       $gap->start($start);
       $gap->end($end);
       return $gap;
   }

   my $last_used_pair;
   my @result;

   foreach my $pair ( @{$hash->{$id}} ) {



       my $self_coord   = &$self_func($pair);
       my $target_coord = &$target_func($pair);

       # if we haven't even reached the start, move on
       if( $self_coord->end < $start ) {
	   next;
       }

       # if we have over run, break
       if( $self_coord->start > $end ) {
	   last;
       }



       if( $start < $self_coord->start ) {
	   # gap detected
	   my $gap = Bio::EnsEMBL::Mapper::Gap->new();
	   $gap->start($start);
	   $gap->end($self_coord->start-1);
	   push(@result,$gap);
           $start = $gap->end+1;
       }

       my ($target_start,$target_end,$target_ori);

       # start is somewhere inside the region
       if( $pair->ori == 1 ) {
	   $target_start = $target_coord->start + ($start - $self_coord->start);
       } else {
	   $target_end   = $target_coord->end - ($start - $self_coord->start);
       }

       # either we are enveloping this map or not. If yes, then end
       # point (self perspective) is determined solely by target. If not
       # we need to adjust

       if( $end > $self_coord->end ) {
	   # enveloped
	   if( $pair->ori == 1 ) {
	       $target_end = $target_coord->end;
	   } else {
	       $target_start = $target_coord->start;
	   }
       } else {
	   # need to adjust end
	   if( $pair->ori == 1 ) {
	       $target_end = $target_coord->start + ($end - $self_coord->start);
	   } else {
	       $target_start = $target_coord->end - ($end - $self_coord->start);
	   }
       }

       my $res = Bio::EnsEMBL::Mapper::Coordinate->new();
       $res->start($target_start);
       $res->end($target_end);
       $res->strand($pair->ori * $strand);
       $res->id($target_coord->id);
       push(@result,$res);

       $last_used_pair = $pair;
       $start = $self_coord->end+1;
   }


   if( !defined $last_used_pair ) {
       my $gap = Bio::EnsEMBL::Mapper::Gap->new();
       $gap->start($start);
       $gap->end($end);
       push(@result,$gap);

   } elsif( &$self_func($last_used_pair)->end < $end ) {
       # gap at the end
       my $gap = Bio::EnsEMBL::Mapper::Gap->new();
       $gap->start(&$self_func($last_used_pair)->end+1);
       $gap->end($end);
       push(@result,$gap);
   }

   if ( $strand == -1 ) {
       @result = reverse ( @result);
   }

   return @result;

}


=head2 add_map_coordinates

    Arg  1      int $id
                id of 'source' sequence
    Arg  2      int $start
                start coordinate of 'source' sequence
    Arg  3      int $end
                end coordinate of 'source' sequence
    Arg  4      int $strand
                relative orientation of source and target (+/- 1)
    Arg  5      int $id
                id of 'targe' sequence
    Arg  6      int $start
                start coordinate of 'targe' sequence
    Arg  7      int $end
                end coordinate of 'targe' sequence
    Function    stores details of mapping between two regions:
                'source' and 'target'
    Returntype  none
    Exceptions  none
    Caller      Bio::EnsEMBL::Mapper

=cut

sub add_map_coordinates{
   my ($self, $contig_id, $contig_start, $contig_end, $contig_ori, $chr_name, $chr_start, $chr_end) = @_;

   
   if( !defined $contig_ori ) {
       $self->throw("Need 7 arguments!");
   }

   if( $contig_start !~ /\d+/ || $chr_start !~ /\d+/ ) {
       $self->throw("Not doable - $contig_start as start or $chr_start as start?");
   }

   if( ($contig_end - $contig_start)  != ($chr_end - $chr_start) ) {
       $self->throw("Cannot deal with mis-lengthed mappings so far");
   }

   my $pair = Bio::EnsEMBL::Mapper::Pair->new();

   my $from = Bio::EnsEMBL::Mapper::Unit->new();
   $from->start($contig_start);
   $from->end($contig_end);
   $from->id($contig_id);

   my $to = Bio::EnsEMBL::Mapper::Unit->new();
   $to->start($chr_start);
   $to->end($chr_end);
   $to->id($chr_name);

   $pair->to($to);
   $pair->from($from);

   $pair->ori($contig_ori);

   # place into hash on both ids

   if( !defined $self->{'_pair_hash_to'}->{$chr_name} ) {
       $self->{'_pair_hash_to'}->{$chr_name} = [];
   }
   push(@{$self->{'_pair_hash_to'}->{$chr_name}},$pair);

   if( !defined $self->{'_pair_hash_from'}->{$contig_id} ) {
       $self->{'_pair_hash_from'}->{$contig_id} = [];
   }
   push(@{$self->{'_pair_hash_from'}->{$contig_id}},$pair);

   $self->_is_sorted(0);
}


=head2 list_pairs

    Arg  1      int $id
                id of 'source' sequence
    Arg  2      int $start
                start coordinate of 'source' sequence
    Arg  3      int $end
                end coordinate of 'source' sequence
    Arg  4      int $type
                nature of transform - gives the type of
                coordinates to be transformed *from*
    Function    list all pairs of mappings in a region
    Returntype  list of Bio::EnsEMBL::Mapper::Pair
    Exceptions  none
    Caller      Bio::EnsEMBL::Mapper

=cut

sub list_pairs{
   my ($self, $id, $start, $end, $type) = @_;


   if( !defined $type ) {
       $self->throw("Must start,end,id,type as coordinates");
   }

   if( $start > $end ) {
     $self->throw("Start is greater than end for id $id, start $start, end $end\n");
   }

   # perhaps a little paranoid/excessive
   if( $self->_is_sorted == 0 ) {
       $self->_sort();
   }


   my @list;
   my $self_func;

   if( $type eq $self->to ) {
       $self_func = \&Bio::EnsEMBL::Mapper::Pair::to;
       if( !defined $self->{'_pair_hash_to'}->{$id} ) {
	   return ();
       }
       @list = @{$self->{'_pair_hash_to'}->{$id}};
   } elsif ( $type eq $self->from ) {
       $self_func = \&Bio::EnsEMBL::Mapper::Pair::from;

       if( !defined $self->{'_pair_hash_from'}->{$id} ) {
	   return ();
       }
       @list = @{$self->{'_pair_hash_from'}->{$id}};
   }

   my @output;
   foreach my $p ( @list ) {

       if( &$self_func($p)->end < $start ) {
	   next;
       }
       if( &$self_func($p)->start > $end ) {
	   last;
       }
       push(@output,$p);
   }
   return @output;
}


=head2 from, to

    Arg  1      Bio::EnsEMBL::Mapper::Unit $id
                id of 'source' sequence
    Function    accessor method form the 'source'
                and 'target' in a Mapper::Pair
    Returntype  Bio::EnsEMBL::Mapper::Unit
    Exceptions  none
    Caller      Bio::EnsEMBL::Mapper

=cut

sub to{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'to'} = $value;
    }
    return $self->{'to'};

}

sub from{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'from'} = $value;
    }
    return $self->{'from'};

}


=head2 _dump

    Arg  1      *FileHandle $fh
    Function    convenience dump function
                possibly useful for debugging
    Returntype  none
    Exceptions  none
    Caller      internal

=cut

sub _dump{
   my ($self,$fh) = @_;

   if( !defined $fh ) {
       $fh = \*STDERR;
   }

   foreach my $id ( keys %{$self->{'_pair_hash_from'}} ) {
       print $fh "From Hash $id\n";
       foreach my $pair ( @{$self->{'_pair_hash_from'}->{$id}} ) {
	   print $fh "    ",$pair->from->start," ",$pair->from->end,":",$pair->to->start," ",$pair->to->end," ",$pair->to->id,"\n";
       }
   }

}


=head2 _sort

    Function    sort function so that all
                mappings are sorted by
                chromosome start
    Returntype  none
    Exceptions  none
    Caller      internal

=cut

sub _sort{
   my ($self) = @_;

   foreach my $id ( keys %{$self->{'_pair_hash_from'}} ) {
       @{$self->{'_pair_hash_from'}->{$id}} = sort { $a->from->start <=> $b->from->start } @{$self->{'_pair_hash_from'}->{$id}};
   }

   foreach my $id ( keys %{$self->{'_pair_hash_to'}} ) {
       @{$self->{'_pair_hash_to'}->{$id}} = sort { $a->to->start <=> $b->to->start } @{$self->{'_pair_hash_to'}->{$id}};
   }

   $self->_is_sorted(1);

}


=head2 _is_sorted

    Arg  1      int $sorted
    Function    toggle for whether the (internal)
                map data are sorted
    Returntype  int
    Exceptions  none
    Caller      internal

=cut

sub _is_sorted{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'_is_sorted'} = $value;
    }
    return $self->{'_is_sorted'};

}


1;
