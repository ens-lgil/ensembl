# EnsEMBL Translation reading writing adaptor for mySQL
#
# Copyright EMBL-EBI 2001
#
# Author: Arne Stabenau
# 
# Date : 21.07.2001
#

=head1 NAME

Bio::EnsEMBL::DBSQL::TranslationAdaptor - MySQL Database queries to generate 
and store translations.

=head1 SYNOPSIS

Translations are stored and fetched with this
object. 

=head1 CONTACT

  ensembl-dev@ebi.ac.uk


=head1 APPENDIX

=cut

package Bio::EnsEMBL::DBSQL::TranslationAdaptor;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::Utils::Exception qw( throw warning deprecate );


@ISA = qw( Bio::EnsEMBL::DBSQL::BaseAdaptor );



=head2 fetch_by_Transcript

  Arg [1]    : none, string, int, Bio::EnsEMBL::Example $formal_parameter_name
    Additional description lines
    list, listref, hashref
  Example    :  ( optional )
  Description: testable description
  Returntype : none, txt, int, float, Bio::EnsEMBL::Example
  Exceptions : none
  Caller     : object::methodname or just methodname

=cut

sub fetch_by_Transcript {
  my ( $self, $transcript ) = @_;

  my $sql = "
    SELECT tl.translation_id, tl.start_exon_id,
           tl.end_exon_id, tl.seq_start, tl.seq_end,
           tlsi.stable_id, tlsi.version
      FROM translation tl
 LEFT JOIN translation_stable_id tlsi
        ON tlsi.translation_id = tl.translation_id
     WHERE tl.transcript_id = ?";

  my $transcript_id = $transcript->dbID();
  my $sth = $self->prepare( $sql );
  $sth->execute( $transcript_id );

  my ( $translation_id, $start_exon_id, $end_exon_id,
       $seq_start, $seq_end, $stable_id, $version ) = 
  $sth->fetchrow_array();

  if( ! defined $translation_id ) {
    return undef;
  }

  my ($start_exon, $end_exon);

  # this will load all the exons whenever we load the translation
  # but I guess thats ok ....

  foreach my $exon (@{$transcript->get_all_Exons()}) {
    if($exon->dbID() == $start_exon_id ) {
      $start_exon = $exon;
    }

    if($exon->dbID() == $end_exon_id ) {
      $end_exon = $exon;
    }
  }

  unless($start_exon && $end_exon) {
     throw("Could not find start or end exon in transcript\n");
  }

  my $translation = Bio::EnsEMBL::Translation->new
   (
     -dbID => $translation_id,
     -adaptor => $self,
     -seq_start => $seq_start,
     -seq_end => $seq_end,
     -start_exon => $start_exon,
     -end_exon => $end_exon,
     -stable_id => $stable_id,
     -version => $version
   );

  return $translation;
}

=head2 fetch_all_by_DBEntry

  Arg [1]    : in $external_id
                the external identifier for the translation to be obtained
  Example    : @trans = @{$trans_adaptor->fetch_all_by_DBEntry($ext_id)}
  Description: retrieves a list of translation with an external database
                idenitifier $external_id
  Returntype : listref of Bio::EnsEMBL::DBSQL::Translation in contig coordinates
  Exceptions : none
  Caller        : ?

=cut

sub fetch_all_by_DBEntry {
  my $self = shift;
  my $external_id = shift;
  my @trans = ();
  warning( "Is this really usefull ???" );

  my $entryAdaptor = $self->db->get_DBEntryAdaptor();
  my @ids = $entryAdaptor->translationids_by_extids($external_id);
  foreach my $trans_id ( @ids ) {
    my $trans = $self->fetch_by_dbID( $trans_id );
    warn $trans_id;
    if( $trans ) {
        push( @trans, $trans );
    }
  }
  return \@trans;
}



=head2 store

  Arg [1]    : Bio::EnsEMBL::Translation $translation
               The translation object to be stored in the database 
  Example    : $transl_id = $translation_adaptor->store($translation);
  Description: Stores a translation object in the database
  Returntype : 
  Exceptions : 
  Caller     : 

=cut

sub store {
  my ( $self, $translation, $transcript_id )  = @_;

  unless( defined $translation->start_Exon->dbID && 
	  defined $translation->end_Exon->dbID ) {
    throw("Attempting to write a translation where the dbIDs of the " .
		 "start and exons are not set. This is most likely to be " .
		 "because you assigned the exons for translation start_exon " .
		 "and translation end_exon to be different in memory " .
		 "objects from your transcript exons - although it could " .
		 "also be an internal error in the adaptors. For your " .
		 "info the exon memory locations are " . 
		 $translation->start_Exon." and ".$translation->end_Exon());
  }

  my $sth = $self->prepare( "
         INSERT INTO translation( seq_start, start_exon_id,
                                  seq_end, end_exon_id, transcript_id) 
         VALUES ( ?,?,?,?,? )");

  $sth->execute( $translation->start(),
		 $translation->start_Exon()->dbID(),
		 $translation->end(),
		 $translation->end_Exon()->dbID(),
	         $transcript_id );

  my $transl_dbID = $sth->{'mysql_insertid'};


  #store object xref mappings to translations

  my $dbEntryAdaptor = $self->db()->get_DBEntryAdaptor();
  #store each of the xrefs for this translation
  foreach my $dbl ( @{$translation->get_all_DBEntries} ) {
     $dbEntryAdaptor->store( $dbl, $transl_dbID, "Translation" );
  }
  
  
  if (defined($translation->stable_id)) {
    if (!defined($translation->version)) {
     throw("Trying to store incomplete stable id information for translation");
    }
    
    my $statement = "INSERT INTO translation_stable_id(translation_id," .
                                   "stable_id,version)".
				     " VALUES(" . $transl_dbID . "," .
				       "'" . $translation->stable_id . "'," .
					 $translation->version . 
					   ")";
        
    my $sth = $self->prepare($statement);
    $sth->execute();
   }

  $translation->dbID( $transl_dbID );
  $translation->adaptor( $self );

  return $transl_dbID;
}


=head2 get_stable_entry_info

 Title   : get_stable_entry_info
 Usage   : $translationAdaptor->get_stable_entry_info($translation)
 Function: gets stable info for translation and places it into the hash
 Returns : 
 Args    : 


=cut

sub get_stable_entry_info {
  my ($self,$translation) = @_;

  deprecate( "This method shouldnt be necessary any more" );

  unless(defined $translation && ref $translation && 
	 $translation->isa('Bio::EnsEMBL::Translation') ) {
    throw("Needs a Translation object, not a [$translation]");
  }

  my $sth = $self->prepare("SELECT stable_id, version 
                            FROM   translation_stable_id 
                            WHERE  translation_id = ?");
  $sth->execute($translation->dbID());

  my @array = $sth->fetchrow_array();
  $translation->{'_stable_id'} = $array[0];
  $translation->{'_version'}   = $array[1];
  
  return 1;
}


sub remove {
  my $self = shift;
  my $translation = shift;

  my $sth = $self->prepare("DELETE FROM translation 
                            WHERE translation_id = ?" );
  $sth->execute( $translation->dbID );
  $sth = $self->prepare("DELETE FROM translation_stable_id 
                         WHERE translation_id = ?" );
  $sth->execute( $translation->dbID );
  $translation->dbID( undef );
  $translation->adaptor(undef);
}

=head2 list_dbIDs

  Arg [1]    : none
  Example    : @translation_ids = @{$translation_adaptor->list_dbIDs()};
  Description: Gets an array of internal ids for all translations in the current db
  Returntype : list of ints
  Exceptions : none
  Caller     : ?

=cut

sub list_dbIDs {
   my ($self) = @_;

   return $self->_list_dbIDs("translation");
}

=head2 list_stable_dbIDs

  Arg [1]    : none
  Example    : @stable_translation_ids = @{$translation_adaptor->list_stable_dbIDs()};
  Description: Gets an array of stable ids for all translations in the current db
  Returntype : list of ints
  Exceptions : none
  Caller     : ?

=cut

sub list_stable_ids {
   my ($self) = @_;

   return $self->_list_dbIDs("translation_stable_id", "stable_id");
}


=head2 fetch_by_dbID

 Title   : fetch_by_dbID
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_dbID {
   my ($self,$dbID,$transcript) = @_;

   deprecate( "This call shouldnt be necessary" );

   if( !defined $transcript ) {
     throw("Translations make no sense outside of their " .
		  "parent Transcript objects. You must retrieve " .
		  "with Transcript parent");
   }

   my $sth = $self->prepare("SELECT translation_id tlid, seq_start, 
                                    start_exon_id, seq_end, end_exon_id 
                             FROM   translation 
                             WHERE  translation_id = ?");
   $sth->execute($dbID);
   my $rowhash = $sth->fetchrow_hashref;

   if( !defined $rowhash ) {
     # assumme this is a translationless transcript deliberately
     return undef;
   }

   my $out = Bio::EnsEMBL::Translation->new();

   $out->start        ($rowhash->{'seq_start'});
   $out->end          ($rowhash->{'seq_end'});


   #search through the transcript's exons for the start and end exons
   my ($start_exon, $end_exon);
   foreach my $exon (@{$transcript->get_all_Exons()}) {
     if($exon->dbID() == $rowhash->{'start_exon_id'}) {
       $start_exon = $exon;
     }

     if($exon->dbID() == $rowhash->{'end_exon_id'}) {
       $end_exon = $exon;
     }
   }
   unless($start_exon && $end_exon) {
     throw("Could not find start or end exon in transcript\n");
   }

   $out->start_Exon($start_exon);
   $out->end_Exon($end_exon);
   $out->dbID($rowhash->{'tlid'});
   $out->adaptor( $self );
   
   return $out;
}

1;
