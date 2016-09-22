#!/usr/bin/perl
package CQS::ConfigUtils;

use strict;
use warnings;
use File::Basename;
use CQS::FileUtils;
use CQS::PBS;
use CQS::ClassFactory;
use CQS::StringUtils;
use CQS::CQSDebug;
use Data::Dumper;
use Hash::Merge qw( merge );

require Exporter;
our @ISA = qw(Exporter);

our %EXPORT_TAGS = (
  'all' => [
    qw(get_option get_java get_cluster get_parameter get_param_file get_directory parse_param_file has_raw_files get_raw_files get_raw_files2 get_run_command get_option_value get_pair_groups get_pair_groups_names get_cqstools get_group_sample_map get_group_samplefile_map get_group_samplefile_map_key)
  ]
);

our @EXPORT = ( @{ $EXPORT_TAGS{'all'} } );

our $VERSION = '0.01';

sub get_option {
  my ( $config, $section, $key, $default ) = @_;

  die "no section $section found!" if !defined $config->{$section};

  my $result = $config->{$section}{$key};
  if ( !defined $result ) {
    if ( !defined $default ) {
      die "Define ${section}::${key} first!";
    }
    else {
      $result = $default;
    }
  }

  return ($result);
}

sub get_cluster {
  my ( $config, $section ) = @_;

  my $cluster_name;
  if ( defined $config->{$section}{cluster} ) {
    $cluster_name = get_option_value( $config->{$section}{cluster}, "slurm" );
  }
  else {
    $cluster_name = get_option_value( $config->{general}{cluster}, "slurm" );
  }

  my $cluster;
  if ( $cluster_name eq "torque" ) {
    $cluster = instantiate("CQS::ClusterTorque");
  }
  else {
    $cluster = instantiate("CQS::ClusterSLURM");
  }

  return ($cluster);
}

sub get_value_in_section_or_general {
  my ( $config, $section, $name, $defaultvalue ) = @_;

  my $result;
  if ( defined $config->{$section}{$name} ) {
    $result = get_option_value( $config->{$section}{$name}, $defaultvalue );
  }
  else {
    $result = get_option_value( $config->{general}{$name}, $defaultvalue );
  }

  return ($result);
}

sub get_java {
  my ( $config, $section ) = @_;
  return ( get_value_in_section_or_general( $config, $section, "java", "java" ) );
}

sub get_parameter {
  my ( $config, $section, $create_directory ) = @_;

  die "no section $section found!" if !defined $config->{$section};

  $create_directory = 1 if !defined($create_directory);

  my $task_name = get_option( $config, $section, "task_name", "" );
  if ( $task_name eq "" ) {
    $task_name = get_option( $config, "general", "task_name" );
  }

  my $cluster = get_cluster(@_);

  my $path_file = get_param_file( $config->{$section}{path_file}, "path_file", 0 );
  if ( !defined $path_file ) {
    $path_file = get_param_file( $config->{general}{path_file}, "path_file", 0 );
  }
  if ( defined $path_file && -e $path_file ) {
    $path_file = "source $path_file";
  }
  else {
    $path_file = "";
  }

  my $refPbs     = get_option( $config, $section, "pbs" );
  my $target_dir = get_option( $config, $section, "target_dir" );
  $target_dir =~ s|//|/|g;
  $target_dir =~ s|/$||g;
  my ( $log_dir, $pbs_dir, $result_dir ) = init_dir( $target_dir, $create_directory );
  my ($pbs_desc) = $cluster->get_cluster_desc($refPbs);

  my $option    = get_option( $config, $section, "option",    "" );
  my $sh_direct = get_option( $config, $section, "sh_direct", 0 );
  
  my $init_command = get_option( $config, $section, "init_command", "" );

  if ($sh_direct) {
    $sh_direct = "bash";
  }
  else {
    $sh_direct = $cluster->get_submit_command();
  }

  my $thread = $cluster->get_cluster_thread($refPbs);
  my $memory = $cluster->get_cluster_memory($refPbs);

  return ( $task_name, $path_file, $pbs_desc, $target_dir, $log_dir, $pbs_dir, $result_dir, $option, $sh_direct, $cluster, $thread, $memory, $init_command );
}

#get parameter which indicates a file. If required, not defined or not exists, die. If defined but not exists, die.
#returned file either undefined or exists.
sub get_param_file {
  my ( $file, $name, $required ) = @_;

  my $result = $file;

  if ($required) {
    if ( !defined $file ) {
      die "$name was not defined!";
    }

    if ( !is_debug() && !-e $file ) {
      die "$name $file defined but not exists!";
    }
  }
  else {
    if ( defined($file) ) {
      if ( $file eq "" ) {
        undef($result);
      }
      elsif ( !is_debug() && !-e $file ) {
        die "$name $file defined but not exists!";
      }
    }
  }
  return ($result);
}

#get parameter which indicates a file. If required, not defined or not exists, die. If defined but not exists, die.
#returned file either undefined or exists.
sub get_directory {
  my ( $config, $section, $name, $required ) = @_;

  die "section $section was not defined!" if !defined $config->{$section};
  die "parameter name must be defined!"   if !defined $name;

  my $result = $config->{$section}{$name};

  if ($required) {
    if ( !defined $result ) {
      die "$name was not defined!";
    }

    if ( !is_debug() && !-e $result ) {
      die "$name $result defined but not exists!";
    }
  }
  else {
    if ( defined($result) ) {
      if ( $result eq "" ) {
        undef($result);
      }
      elsif ( !is_debug() && !-e $result ) {
        die "$name $result defined but not exists!";
      }
    }
  }
  return ($result);
}

sub get_cqstools {
  my ( $config, $section, $required ) = @_;
  my $cqstools = get_param_file( $config->{$section}{cqs_tools}, "cqs_tools", 0 );
  if ( !defined $cqstools ) {
    $cqstools = get_param_file( $config->{$section}{cqstools}, "cqstools", $required );
  }
  return ($cqstools);
}

sub parse_param_file {
  my ( $config, $section, $key, $required ) = @_;

  die "section $section was not defined!" if !defined $config->{$section};
  die "parameter key must be defined!" if !defined $key;

  if ( defined $config->{$section}{$key} ) {
    return $config->{$section}{$key};
  }

  my $key_ref = $key . "_ref";
  if ( defined $config->{$section}{$key_ref} ) {
    my $refSectionName = $config->{$section}{$key_ref};
    my $pattern;
    if ( ref($refSectionName) eq 'ARRAY' ) {
      my @parts = @{$refSectionName};
      if ( scalar(@parts) == 2 ) {
        $pattern        = $parts[1];
        $refSectionName = $parts[0];
      }
      else {
        $refSectionName = $parts[0];
      }
    }
    die "section $refSectionName was not defined!" if !defined $config->{$refSectionName};
    if ( defined $config->{$refSectionName}{class} ) {
      my $myclass = instantiate( $config->{$refSectionName}{class} );
      my $result = $myclass->result( $config, $refSectionName, $pattern );
      foreach my $k ( sort keys %{$result} ) {
        my @files = @{ $result->{$k} };
        if (scalar(@files) > 0){
          return $files[0];
        }
      }
      die "section $refSectionName return nothing!";
    }
  }

  if ($required) {
    die "define ${section}::${key} first.";
  }

  return undef;
}

sub has_raw_files {
  my ( $config, $section, $mapname ) = @_;

  if ( !defined $mapname ) {
    $mapname = "source";
  }

  my $mapname_ref        = $mapname . "_ref";
  my $mapname_config_ref = $mapname . "_config_ref";

  return ( defined $config->{$section}{$mapname} ) || ( defined $config->{$section}{$mapname_ref} ) || ( defined $config->{$section}{$mapname_config_ref} );
}

sub do_get_raw_files {
  my ( $config, $section, $returnself, $mapname, $pattern ) = @_;

  die "section $section was not defined!" if !defined $config->{$section};

  if ( !defined $mapname ) {
    $mapname = "source";
  }
  my $mapname_ref        = $mapname . "_ref";
  my $mapname_config_ref = $mapname . "_config_ref";

  if ( defined $config->{$section}{$mapname} ) {
    return ( $config->{$section}{$mapname}, 1 );
  }

  if ( defined $config->{$section}{$mapname_ref} || defined $config->{$section}{$mapname_config_ref} ) {
    my $refmap = {};
    if ( defined $config->{$section}{$mapname_ref} ) {

      #in same config
      my $targetSection = $config->{$section}{$mapname_ref};

      if ( ref($targetSection) eq 'HASH' ) {
        return ( $targetSection, 1 );
      }

      if ( ref($targetSection) eq 'ARRAY' ) {
        my @parts      = @{$targetSection};
        my $partlength = scalar(@parts);
        for ( my $index = 0 ; $index < $partlength ; ) {
          if ( !defined $config->{ $parts[$index] } ) {
            die "undefined section $parts[$index]";
          }

          if ( $index == ( $partlength - 1 ) || defined $config->{ $parts[ $index + 1 ] } ) {
            $refmap->{$index} = { config => $config, section => $parts[$index], pattern => $pattern };
            $index++;
          }
          else {
            $refmap->{$index} = { config => $config, section => $parts[$index], pattern => $parts[ $index + 1 ] };
            $index += 2;
          }
        }
      }
      else {
        if ( !defined $config->{$targetSection} ) {
          die "undefined section $targetSection";
        }
        $refmap->{1} = { config => $config, section => $targetSection, pattern => $pattern };
      }
    }
    else {

      #in another config, has to be array
      my $refSectionName = $config->{$section}{$mapname_config_ref};
      if ( !( ref($refSectionName) eq 'ARRAY' ) ) {
        die "$mapname_config_ref has to be defined as ARRAY with [config, section, pattern]";
      }
      my @parts      = @{$refSectionName};
      my $partlength = scalar(@parts);
      for ( my $index = 0 ; $index < $partlength - 1 ; ) {
        my $targetConfig  = $parts[$index];
        my $targetSection = $parts[ $index + 1 ];

        if ( !( ref($targetConfig) eq 'HASH' ) ) {
          die
"$mapname_config_ref has to be defined as ARRAY with [config1, section1, pattern1,config2, section2, pattern2] or [config1, section1,config2, section2] format. config should be hash and section should be string";
        }

        if ( !defined $targetConfig->{$targetSection} ) {
          die "undefined section $targetSection in $mapname_config_ref of $section";
        }

        if ( $index == ( $partlength - 2 ) || ref( $parts[ $index + 2 ] ) eq 'HASH' ) {
          $refmap->{$index} = { config => $targetConfig, section => $targetSection, pattern => $pattern };
          $index += 2;
        }
        else {
          $refmap->{$index} = { config => $targetConfig, section => $targetSection, pattern => $parts[ $index + 2 ] };
          $index += 3;
        }
      }
    }

    #print Dumper($refmap);

    my %result = ();
    my @sortedKeys = sort { $a <=> $b } keys %$refmap;
    for my $index (@sortedKeys) {
      my $values       = $refmap->{$index};
      my $targetConfig = $values->{config};
      my $section      = $values->{section};
      my $pattern      = $values->{pattern};

      my %myres = ();
      if ( defined $targetConfig->{$section}{class} ) {
        my $myclass = instantiate( $targetConfig->{$section}{class} );
        %myres = %{ $myclass->result( $targetConfig, $section, $pattern ) };
      }
      else {
        my ( $res, $issource ) = do_get_raw_files( $targetConfig, $section, 1, undef, $pattern );
        %myres = %{$res};
      }

      my $refcount = keys %myres;
      for my $mykey ( keys %myres ) {
        my $myvalues = $myres{$mykey};
        if(ref($myvalues) eq ''){
          $myvalues = [$myvalues];
        }
        
        if ( ( ref($myvalues) eq 'ARRAY' ) && ( scalar( @{$myvalues} ) > 0 ) ) {
          if ( exists $result{$mykey} ) {
            my $oldvalues = $result{$mykey};
            if ( ref($oldvalues) eq 'ARRAY' ) {
              my @merged = ( @{$oldvalues}, @{$myvalues} );

              #print "merged ARRAY ", Dumper(\@merged);
              $result{$mykey} = \@merged;
            }
            else {
              die "The source of $section->$mapname should be all HASH or all ARRAY";
            }
          }
          else {
            $result{$mykey} = $myvalues;
          }
        }

        if ( ( ref($myvalues) eq 'HASH' ) && ( scalar( keys %{$myvalues} ) > 0 ) ) {
          if ( exists $result{$mykey} ) {
            my $oldvalues = $result{$mykey};
            if ( ref($oldvalues) eq 'HASH' ) {
              $result{$mykey} = merge( $oldvalues, $myvalues );
            }
            else {
              die "The source of $section->$mapname should be all HASH or all ARRAY";
            }
          }
          else {
            $result{$mykey} = $myvalues;
          }
        }
      }

      #print "--------------- $section, $mapname, $index ----------------\n";
      #print Dumper(%result);
    }

    my $final = \%result;
    return ( $final, 0 );
  }

  if ($returnself) {
    if ( defined $pattern ) {
      my $result = {};
      for my $key ( sort keys %{ $config->{$section} } ) {
        my $values = $config->{$section}{$key};
        $result->{$key} = filter_array( $values, $pattern );
      }
      return ( $result, 0 );
    }
    else {
      return ( $config->{$section}, 0 );
    }
  }
  else {
    die "define $mapname or $mapname_ref or $mapname_config_ref for $section";
  }
}

sub get_raw_files {
  my ( $config, $section, $mapname, $pattern ) = @_;
  my ( $result, $issource ) = do_get_raw_files( $config, $section, 0, $mapname, $pattern );
  return ($result);
}

#return raw files and if the raw files are extracted from source directly
sub get_raw_files2 {
  my ( $config, $section, $mapname, $pattern ) = @_;
  return do_get_raw_files( $config, $section, 0, $mapname, $pattern );
}

sub get_run_command {
  my $sh_direct = shift;
  return ("MYCMD=\"$sh_direct\" \n");
}

sub get_run_command_old {
  my $sh_direct = shift;
  if ($sh_direct) {
    return ("MYCMD=\"bash\" \n");
  }
  else {
    return ("type -P qsub &>/dev/null && MYCMD=\"qsub\" || MYCMD=\"bash\" \n");
  }
}

sub get_option_value {
  my ( $value, $defaultValue ) = @_;
  if ( !defined $value ) {
    return ($defaultValue);
  }
  else {
    return ($value);
  }
}

sub get_pair_groups {
  my ( $pairs, $pair_name ) = @_;
  my $group_names;
  my $ispaired       = 0;
  my $tmpgroup_names = $pairs->{$pair_name};
  if ( ref($tmpgroup_names) eq 'HASH' ) {
    $group_names = $tmpgroup_names->{"groups"};
    $ispaired    = $tmpgroup_names->{"paired"};
  }
  else {
    $group_names = $tmpgroup_names;
  }
  if ( !defined $ispaired ) {
    $ispaired = 0;
  }
  return ( $ispaired, $group_names );
}

sub get_pair_groups_names {
  my ( $pairs, $pair_name ) = @_;
  my $group_names;
  my $pairedNames;
  my $tmpgroup_names = $pairs->{$pair_name};
  if ( ref($tmpgroup_names) eq 'HASH' ) {
    $group_names = $tmpgroup_names->{"groups"};
    $pairedNames = $tmpgroup_names->{"paired"};
  }
  else {
    $group_names = $tmpgroup_names;
  }
  return ( $pairedNames, $group_names );
}

#Return
#{
#  groupName1 => [
#    [sample_name1_1, sampleFile1_1_1, sampleFile1_1_2],
#    [sample_name1_2, sampleFile1_2_1, sampleFile1_2_2],
#  ],
#  groupName2 => [
#    [sample_name2_1, sampleFile2_1_1, sampleFile2_1_2],
#    [sample_name2_2, sampleFile2_2_1, sampleFile2_2_2],
#  ],
#}
sub get_group_sample_map {
  my ( $config, $section, $samplePattern ) = @_;

  my $raw_files = get_raw_files( $config, $section, "source", $samplePattern );
  my $groups = get_raw_files( $config, $section, "groups" );
  my %group_sample_map = ();
  for my $group_name ( sort keys %{$groups} ) {
    my @samples = @{ $groups->{$group_name} };
    my @gfiles  = ();
    foreach my $sample_name (@samples) {
      my @bam_files = @{ $raw_files->{$sample_name} };
      my @sambam = ( $sample_name, @bam_files );
      push( @gfiles, \@sambam );
    }
    $group_sample_map{$group_name} = \@gfiles;
  }

  return \%group_sample_map;
}

#Return
#{
#  groupName1 => [sampleFile1_1_1, sampleFile1_1_2, sampleFile1_2_1, sampleFile1_2_2],
#  groupName2 => [sampleFile2_1_1, sampleFile2_1_2, sampleFile2_2_1, sampleFile2_2_2],
#}
sub get_group_samplefile_map {
  my ( $config, $section, $sample_pattern ) = @_;
  return get_group_samplefile_map_key( $config, $section, $sample_pattern, "groups" );
}

sub get_group_samplefile_map_key {
  my ( $config, $section, $sample_pattern, $group_key ) = @_;

  my $raw_files = get_raw_files( $config, $section, "source", $sample_pattern );
  my $groups = get_raw_files( $config, $section, $group_key );
  my %group_sample_map = ();
  for my $group_name ( sort keys %{$groups} ) {
    my @gfiles        = ();
    my $group_samples = $groups->{$group_name};
    if ( ref $group_samples eq ref "" ) {
      push( @gfiles, $group_samples );
    }
    else {
      my @samples = @{$group_samples};
      foreach my $sample_name (@samples) {
        my @bam_files = @{ $raw_files->{$sample_name} };
        foreach my $bam_file (@bam_files) {
          push( @gfiles, $bam_file );
        }
      }
    }
    $group_sample_map{$group_name} = \@gfiles;
  }
  return \%group_sample_map;
}

1;
