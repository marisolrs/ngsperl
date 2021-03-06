#!/usr/bin/perl
package Pipeline::PipelineUtils;

use strict;
use warnings;
use CQS::FileUtils;
use CQS::SystemUtils;
use CQS::ConfigUtils;
use CQS::ClassFactory;
use Data::Dumper;
use Hash::Merge qw( merge );

require Exporter;
our @ISA = qw(Exporter);

our %EXPORT_TAGS = (
  'all' => [
    qw(getValue initPipelineOptions addPreprocess addFastQC addBlastn addBowtie addBamStat
      getDEseq2TaskName addDEseq2 addDeseq2Visualization addDeseq2SignificantSequenceBlastn
      getBatchGroups addHomerMotif addHomerAnnotation addEnhancer writeDesignTable addMultiQC
      getNextFolderIndex addCleanBAM getReportDir getSequenceTaskClassname)
  ]
);

our @EXPORT = ( @{ $EXPORT_TAGS{'all'} } );

our $VERSION = '0.01';

sub getValue {
  my ( $def, $name, $defaultValue ) = @_;
  if ( defined $def->{$name} ) {
    return $def->{$name};
  }
  elsif ( defined $defaultValue ) {
    return $defaultValue;
  }
  else {
    die "Define $name in user definition first.";
  }
}

sub getNextFolderIndex {
  my ($def) = @_;

  my $result = "";
  my $add_folder_index = getValue( $def, "add_folder_index", 0 );
  if ($add_folder_index) {
    my $folder_index = getValue( $def, "folder_index", 1 );
    $result = sprintf( "T%03d_", $folder_index );
    $def->{folder_index} = $folder_index + 1;
  }

  return $result;
}

sub addFastQC {
  my ( $config, $def, $individual, $summary, $fastqcTask, $source_ref, $parentDir ) = @_;
  $config->{"$fastqcTask"} = {
    class      => "QC::FastQC",
    perform    => 1,
    target_dir => $parentDir . "/" . getNextFolderIndex($def) . "$fastqcTask",
    option     => "",
    source_ref => $source_ref,
    cluster    => $def->{cluster},
    sh_direct  => 1,
    pbs        => {
      "email"    => $def->{email},
      "nodes"    => "1:ppn=1",
      "walltime" => "2",
      "mem"      => "10gb"
    },
  };

  my $summaryTask = $fastqcTask . "_summary";

  $config->{$summaryTask} = {
    class      => "QC::FastQCSummary",
    perform    => 1,
    target_dir => $config->{"$fastqcTask"}->{target_dir},
    cqstools   => $def->{cqstools},
    option     => "",
    cluster    => $def->{cluster},
    sh_direct  => 1,
    pbs        => {
      "email"    => $def->{email},
      "nodes"    => "1:ppn=1",
      "walltime" => "2",
      "mem"      => "10gb"
    },
  };
  push @$individual, $fastqcTask;
  push @$summary,    $summaryTask;
}

sub addBlastn {
  my ( $config, $def, $summary, $blastTask, $fastaTask, $filePattern, $parentDir ) = @_;

  $config->{$blastTask} = {
    class      => "Blast::Blastn",
    perform    => 1,
    target_dir => $parentDir . "/" . getNextFolderIndex($def) . "$blastTask",
    option     => "",
    source_ref => [ $fastaTask, $filePattern ],
    sh_direct  => 0,
    localdb    => $def->{blast_localdb},
    cluster    => $def->{cluster},
    pbs        => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=" . $def->{max_thread},
      "walltime"  => "10",
      "mem"       => "10gb"
    }
  };

  push @$summary, $blastTask;
}

sub addBowtie {
  my ( $config, $def, $individual, $taskName, $parentDir, $bowtieIndex, $sourceRef, $bowtieOption ) = @_;

  $config->{$taskName} = {
    class                 => "Alignment::Bowtie1",
    perform               => 1,
    target_dir            => $parentDir . "/" . getNextFolderIndex($def) . $taskName,
    option                => $bowtieOption,
    source_ref            => $sourceRef,
    bowtie1_index         => $bowtieIndex,
    samonly               => 0,
    sh_direct             => 1,
    mappedonly            => 1,
    cluster               => $def->{cluster},
    output_to_same_folder => $def->{bowtie1_output_to_same_folder},
    pbs                   => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=" . $def->{max_thread},
      "walltime"  => "72",
      "mem"       => "40gb"
    },
  };

  push @$individual, $taskName;
}

sub addBamStat {
  my ( $config, $def, $summary, $taskName, $targetDir, $sourceRef ) = @_;

  $config->{$taskName} = {
    class       => "CQS::UniqueR",
    target_dir  => $targetDir,
    perform     => 1,
    rtemplate   => "../Samtools/BamStat.r",
    output_file => ".bamstat.csv",
    sh_direct   => 1,
    cluster     => $def->{cluster},
    pbs         => {
      parameterSampleFile1_ref => $sourceRef,
      "email"                  => $def->{email},
      "emailType"              => $def->{emailType},
      "nodes"                  => "1:ppn=1",
      "walltime"               => "10",
      "mem"                    => "10gb"
    },
  };
  push @$summary, $taskName;
}

sub getDEseq2TaskName {
  my ( $taskKey, $libraryKey, $def ) = @_;
  my $result = "deseq2_" . $taskKey;
  if ( defined $libraryKey ) {
    $result = $result . "_" . $libraryKey;
  }
  if ( defined $def->{DE_task_suffix} ) {
    $result = $result . $def->{DE_task_suffix};
  }
  return $result;
}

sub getReportDir {
  my $def        = shift;
  my $report_dir = undef;
  if ( defined $def->{"output_to_report_dir"} && $def->{"output_to_report_dir"} ) {
    $report_dir = $def->{target_dir} . "/report";
  }
  return ($report_dir);
}

sub addDEseq2 {
  my ( $config, $def, $summary, $taskKey, $countfileRef, $deseq2Dir, $DE_min_median_read, $libraryFile, $libraryKey ) = @_;

  my $taskName = getDEseq2TaskName( $taskKey, $libraryKey, $def );

  my $libraryFileKey = "library_file";
  if ( ref($libraryFile) eq 'ARRAY' ) {
    $libraryFileKey = "library_file_ref";
  }

  $config->{$taskName} = {
    class                        => "Comparison::DESeq2",
    perform                      => 1,
    target_dir                   => $deseq2Dir . "/" . getNextFolderIndex($def) . "$taskName",
    output_to_dir                => getReportDir($def),
    option                       => "",
    source_ref                   => "pairs",
    groups_ref                   => "groups",
    countfile_ref                => $countfileRef,
    sh_direct                    => 1,
    show_label_PCA               => $def->{show_label_PCA},
    use_pearson_in_hca           => $def->{use_pearson_in_hca},
    show_DE_gene_cluster         => $def->{DE_show_gene_cluster},
    pvalue                       => $def->{DE_pvalue},
    fold_change                  => $def->{DE_fold_change},
    min_median_read              => $DE_min_median_read,
    add_count_one                => $def->{DE_add_count_one},
    top25only                    => $def->{DE_top25only},
    detected_in_both_group       => $def->{DE_detected_in_both_group},
    use_raw_p_value              => $def->{DE_use_raw_pvalue},
    text_size                    => $def->{DE_text_size},
    cluster                      => $def->{cluster},
    export_significant_gene_name => $def->{DE_export_significant_gene_name},
    cooksCutoff                  => $def->{DE_cooksCutoff},
    $libraryFileKey              => $libraryFile,
    library_key                  => $libraryKey,
    pbs                          => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=". $def->{max_thread},
      "walltime"  => "10",
      "mem"       => "20gb"
    },
  };

  if ( ref($countfileRef) eq "ARRAY" ) {
    $config->{$taskName}{countfile_ref} = $countfileRef;
  }
  else {
    $config->{$taskName}{countfile} = $countfileRef;
  }

  push @$summary, $taskName;
  return $taskName;
}

sub addDeseq2Visualization {
  my ( $config, $def, $summary, $taskKey, $deseq2Tasks, $dataVisualizationDir, $layoutName, $libraryKey ) = @_;

  my $taskName = getDEseq2TaskName( $taskKey, $libraryKey, $def ) . "_vis";

  my $deseq2FileRef = [];
  for my $deseq2Task (@$deseq2Tasks) {
    push @$deseq2FileRef, ( getDEseq2TaskName( $deseq2Task, $libraryKey, $def ), "_DESeq2.csv\$" );
  }

  $config->{$taskName} = {
    class                    => "CQS::UniqueR",
    perform                  => 1,
    target_dir               => $dataVisualizationDir . "/" . getNextFolderIndex($def) . "$taskName",
    output_to_dir            => getReportDir($def),
    rtemplate                => "DESeq2_all_vis.R",
    output_file              => ".${taskKey}.DESeq2.Matrix",
    output_file_ext          => ".png",
    remove_empty_parameter   => 1,
    parameterSampleFile1_ref => $deseq2FileRef,
    parameterSampleFile2     => $def->{$layoutName},
    rCode                    => 'useRawPvalue=' . $def->{DE_use_raw_pvalue} . ";",
    sh_direct                => 1,
    cluster                  => $def->{cluster},
    pbs                      => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=1",
      "walltime"  => "1",
      "mem"       => "10gb"
    },
  };
  push @$summary, $taskName;
  return $taskName;
}

sub addDeseq2SignificantSequenceBlastn {
  my ( $config, $def, $summary, $deseq2Task, $parentDir ) = @_;

  my $fastaTask = $deseq2Task . "_sequences";
  $config->{$fastaTask} = {
    class                  => "Blast::DESeq2SignificantReadToFasta",
    perform                => 1,
    target_dir             => $parentDir . "/" . getNextFolderIndex($def) . "$fastaTask",
    option                 => "",
    remove_empty_parameter => 1,
    source_ref             => [ $deseq2Task, "_DESeq2_sig.csv\$" ],
    sh_direct              => 1,
    cluster                => $def->{cluster},
    pbs                    => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=1",
      "walltime"  => "2",
      "mem"       => "10gb"
    }
  };

  push @$summary, ($fastaTask);

  addBlastn( $config, $def, $summary, $fastaTask . "_blastn", $fastaTask, ".fasta\$", $parentDir );
}

sub getBatchGroups {
  my ($def) = @_;
  my $files = $def->{files};
  my $result;
  my $layout;

  if ( defined $def->{batch_groups_name_file_regex} ) {
    for my $regexName ( keys %{ $def->{batch_groups_name_file_regex} } ) {
      my $regexHash = $def->{batch_groups_name_file_regex}->{$regexName};
      my $fileRegex = $regexHash->{file};
      my $nameRegex = $regexHash->{name};

      my $lCols   = [];
      my $lRows   = [];
      my $lGroups = [];
      $layout->{$regexName} = {
        "Col_Group" => $lCols,
        "Row_Group" => $lRows,
        "Groups"    => $lGroups
      };
      my $pushed    = {};
      my $curGroups = {};
      $result->{$regexName} = $curGroups;

      for my $sample ( keys %$files ) {
        my $sampleFile = $files->{$sample}[0];
        my $group;
        if ( $sampleFile =~ /$fileRegex/igs ) {
          my $fileGroupName = $1;
          if ( $sample =~ /$nameRegex/igs ) {
            my $sampleGroupName = $1;
            my $groupName       = $sampleGroupName . "_" . $fileGroupName;
            if ( !exists( $pushed->{$groupName} ) ) {
              push( @$lCols,   $fileGroupName );
              push( @$lRows,   $sampleGroupName );
              push( @$lGroups, $groupName );
              $pushed->{$groupName} = "";
            }

            if ( !defined $curGroups->{$groupName} ) {
              $curGroups->{$groupName} = [];
            }
            my $groups = $curGroups->{$groupName};
            push @$groups, $sample;
          }
          else {
            die( $sample . " didn't match with name regex " . $nameRegex );
          }
        }
        else {
          die( $sample . " didn't match with file regex " . $fileRegex . " : " . $sampleFile );
        }
      }
    }
  }
  elsif ( defined $def->{batch_groups_file_regex} ) {
    for my $regexName ( keys %{ $def->{batch_groups_file_regex} } ) {
      my $regex     = $def->{batch_groups_file_regex}->{$regexName};
      my $curGroups = {};
      $result->{$regexName} = $curGroups;
      for my $sample ( keys %$files ) {
        my $sampleFile = $files->{$sample}[0];
        my $group;
        if ( $sampleFile =~ /$regex/igs ) {
          my $groupName = $1;
          if ( !defined $curGroups->{$groupName} ) {
            $curGroups->{$groupName} = [];
          }
          my $groups = $curGroups->{$groupName};
          push @$groups, $sample;
        }
        else {
          die( $sample . " didn't match with regex " . $regex . " : " . $sampleFile );
        }
      }
    }
  }
  elsif ( defined $def->{batch_groups_name_regex} ) {
    for my $regexName ( keys %{ $def->{batch_groups_file_regex} } ) {
      my $regex     = $def->{batch_groups_name_regex}->{$regexName};
      my $curGroups = {};
      $result->{$regexName} = $curGroups;
      for my $sample ( keys %$files ) {
        my $group;
        if ( $sample =~ /$regex/igs ) {
          my $groupName = $1;
          if ( !defined $curGroups->{$groupName} ) {
            $curGroups->{$groupName} = [];
          }
          my $groups = $curGroups->{$groupName};
          push @$groups, $sample;
        }
        else {
          die( $sample . " didn't match with regex " . $regex );
        }
      }
    }
  }
  elsif ( defined $def->{batch_groups} ) {
    $result = $def->{batch_groups};
  }

  return ( $result, $layout );
}

sub addHomerMotif {
  my ( $config, $def, $summary, $target_dir, $callName, $callFilePattern ) = @_;
  my $homerName = $callName . "_homer_motifs";
  $config->{$homerName} = {
    class        => "Homer::FindMotifs",
    option       => getValue( $def, "homer_option" ),
    perform      => 1,
    target_dir   => $target_dir . "/" . getNextFolderIndex($def) . $homerName,
    source_ref   => [ $callName, $callFilePattern ],
    homer_genome => getValue( $def, "homer_genome" ),
    sh_direct    => 1,
    pbs          => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=1",
      "walltime"  => "1",
      "mem"       => "10gb"
    },
  };
  push @$summary, ($homerName);
  return $homerName;
}

sub addHomerAnnotation {
  my ( $config, $def, $summary, $target_dir, $callName, $callFilePattern ) = @_;
  my $homerName = $callName . "_homer_annotation";
  $config->{$homerName} = {
    class        => "Homer::Annotation",
    option       => getValue( $def, "homer_option" ),
    perform      => 1,
    target_dir   => $target_dir . "/" . getNextFolderIndex($def) . $homerName,
    source_ref   => [ $callName, $callFilePattern ],
    homer_genome => getValue( $def, "homer_genome" ),
    sh_direct    => 1,
    pbs          => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=1",
      "walltime"  => "1",
      "mem"       => "10gb"
    },
  };
  push @$summary, ($homerName);
  return $homerName;
}

sub addEnhancer {
  my ( $config, $def, $individual, $summary, $target_dir, $enhancerName, $bam_ref, $peak_ref ) = @_;
  $config->{$enhancerName} = {
    class         => "Chipseq::Enhancer",
    perform       => 1,
    target_dir    => "${target_dir}/" . getNextFolderIndex($def) . $enhancerName,
    option        => "",
    source_ref    => $bam_ref,
    treatments    => $def->{treatments},
    peaks_ref     => $peak_ref,
    pipeline_dir  => getValue( $def, "enhancer_folder" ),
    genome        => getValue( $def, "enhancer_genome" ),
    genome_path   => getValue( $def, "enhancer_genome_path" ),
    gsea_path     => getValue( $def, "enhancer_gsea_path" ),
    gmx_path      => getValue( $def, "enhancer_gmx_path" ),
    cpg_path      => getValue( $def, "enhancer_cpg_path" ),
    activity_file => $def->{enhancer_activity_file},
    sh_direct     => 1,
    pbs           => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=1",
      "walltime"  => "72",
      "mem"       => "40gb"
    },
  };
  push @$individual, ($enhancerName);

  my $enhancerVis = $enhancerName . "_vis";
  $config->{$enhancerVis} = {
    class                    => "CQS::UniqueR",
    perform                  => 1,
    target_dir               => "${target_dir}/" . getNextFolderIndex($def) . $enhancerVis,
    option                   => "",
    rtemplate                => "../Chipseq/enhancerVis.R",
    output_file              => ".enhancer",
    output_file_ext          => ".log.tss.png;.log.distal.png;.tss.tsv;.distal.tsv",
    sh_direct                => 1,
    parameterSampleFile1_ref => [ "$enhancerName", ".txt\$" ],
    sh_direct                => 1,
    pbs                      => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=1",
      "walltime"  => "72",
      "mem"       => "40gb"
    },
  };
  push @$summary, $enhancerVis;

  my $enhancerVisCor = $enhancerVis . "_correlation";
  $config->{$enhancerVisCor} = {
    class                    => "CQS::CountTableGroupCorrelation",
    perform                  => 1,
    suffix                   => "_corr",
    target_dir               => $config->{$enhancerVis}->{target_dir},
    rtemplate                => "countTableVisFunctions.R,countTableGroupCorrelation.R",
    output_file              => "parameterSampleFile1",
    output_file_ext          => ".Correlation.png",
    parameterSampleFile1_ref => [ $enhancerVis, ".tsv\$" ],
    sh_direct                => 1,
    pbs                      => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=1",
      "walltime"  => "1",
      "mem"       => "10gb"
    },
  };
  push @$summary, $enhancerVisCor;
}

sub addMultiQC {
  my ( $config, $def, $summary, $target_dir, $root_dir, $option ) = @_;
  $config->{multiqc} = {
    class         => "QC::MultiQC",
    option        => getValue( $def, "multiqc_option", "" ),
    perform       => 1,
    target_dir    => $target_dir . "/" . getNextFolderIndex($def) . "multiqc",
    output_to_dir => getReportDir($def),
    root_dir      => $root_dir,
    sh_direct     => 1,
    pbs           => {
      "email"     => $def->{email},
      "emailType" => $def->{emailType},
      "nodes"     => "1:ppn=1",
      "walltime"  => "1",
      "mem"       => "10gb"
    },
  };
  push @$summary, ("multiqc");
  return "multiqc";
}

sub addCleanBAM {
  my ( $config, $def, $individual, $task_name, $target_dir, $bam_ref, $pairend ) = @_;

  my $cleanbam_option;
  my $minimum_insert_size;
  my $maximum_insert_size;
  if ($pairend) {
    $cleanbam_option     = "-f 3 -F 3852";
    $minimum_insert_size = getValue( $def, "minimum_insert_size" );
    $maximum_insert_size = getValue( $def, "maximum_insert_size" );
  }
  else {
    $cleanbam_option = "-F 3844";

  }

  $config->{$task_name} = {
    class                   => "ATACseq::CleanBam",
    perform                 => 1,
    target_dir              => $target_dir,
    option                  => $cleanbam_option,
    source_ref              => $bam_ref,
    picard_jar              => getValue( $def, "picard_jar" ),
    remove_chromosome       => $def->{remove_chromosome},
    keep_chromosome         => $def->{keep_chromosome},
    minimum_maq             => getValue( $def, "minimum_maq" ),
    minimum_insert_size     => $minimum_insert_size,
    maximum_insert_size     => $maximum_insert_size,
    blacklist_file          => $def->{blacklist_file},
    pairend                 => $pairend,
    is_sorted_by_coordinate => 1,
    sh_direct               => 0,
    pbs                     => {
      "email"    => $def->{email},
      "nodes"    => "1:ppn=1",
      "walltime" => "240",
      "mem"      => "40gb"
    },
  };
  push @$individual, $task_name;
}

sub writeDesignTable {
  my ( $target_dir, $section, $designtable, $bamfiles, $peaksfiles, $peakSoftware, $merged, $task_name, $treatments, $controls ) = @_;

  my $defaultTissue = getValue( $designtable, "Tissue", "" );
  my $defaultFactor = getValue( $designtable, "Factor", "" );

  my $result = {};

  if ($merged) {
    my $mapFileName = "${task_name}.config.txt";
    my $mapfile     = $target_dir . "/" . $mapFileName;
    open( my $map, ">$mapfile" ) or die "Cannot create $mapfile";
    print $map "SampleID\tTissue\tFactor\tCondition\tReplicate\tbamReads\tControlID\tbamControl\tPeaks\tPeakCaller\n";
    for my $name ( sort keys %$designtable ) {
      if ( $name eq "Tissue" || $name eq "Factor" ) {
        next;
      }

      my $sampleList        = $designtable->{$name};
      my $defaultNameTissue = getValue( $sampleList, "Tissue", $defaultTissue );
      my $defaultNameFactor = getValue( $sampleList, "Factor", $defaultFactor );

      for my $sampleName ( sort keys %$sampleList ) {
        if ( $sampleName eq "Tissue" || $sampleName eq "Factor" || $sampleName eq "Comparison" ) {
          next;
        }

        my $entryMap = getValue( $sampleList, $sampleName );
        my $tissue   = getValue( $entryMap,   "Tissue", $defaultNameTissue );
        my $factor   = getValue( $entryMap,   "Factor", $defaultNameFactor );
        my $condition = $entryMap->{Condition} or die "Define Condition for $sampleName in designtable of section $section";
        my $replicate = $entryMap->{Replicate} or die "Define Replicate for $sampleName in designtable of section $section";
        my $peakFile  = $peaksfiles->{$sampleName}->[0];

        my $sampleId   = $treatments->{$sampleName}->[0];
        my $bamReads   = $bamfiles->{$sampleId}[0];
        my $controlId  = "";
        my $bamControl = "";

        if ( defined $controls ) {
          $controlId  = $controls->{$sampleName}->[0];
          $bamControl = $bamfiles->{$controlId}[0];
        }

        print $map $sampleId . "\t"
          . $tissue . "\t"
          . $factor . "\t"
          . $condition . "\t"
          . $replicate . "\t"
          . $bamReads . "\t"
          . $controlId . "\t"
          . $bamControl . "\t"
          . $peakFile . "\t"
          . $peakSoftware . "\n";
      }
    }
    close($map);

    $result->{$task_name} = $mapfile;
  }
  else {
    for my $name ( sort keys %$designtable ) {
      if ( $name eq "Tissue" || $name eq "Factor" ) {
        next;
      }

      my $sampleList        = $designtable->{$name};
      my $defaultNameTissue = getValue( $sampleList, "Tissue", $defaultTissue );
      my $defaultNameFactor = getValue( $sampleList, "Factor", $defaultFactor );

      my $curdir      = create_directory_or_die( $target_dir . "/" . $name );
      my $mapFileName = "${name}.config.txt";
      my $mapfile     = $curdir . "/" . $mapFileName;
      open( my $map, ">$mapfile" ) or die "Cannot create $mapfile";
      print $map "SampleID\tTissue\tFactor\tCondition\tReplicate\tbamReads\tControlID\tbamControl\tPeaks\tPeakCaller\n";
      for my $sampleName ( sort keys %$sampleList ) {
        if ( $sampleName eq "Tissue" || $sampleName eq "Factor" || $sampleName eq "Comparison" ) {
          next;
        }

        my $entryMap = getValue( $sampleList, $sampleName );
        my $tissue   = getValue( $entryMap,   "Tissue", $defaultNameTissue );
        my $factor   = getValue( $entryMap,   "Factor", $defaultNameTissue );
        my $condition = $entryMap->{Condition} or die "Define Condition for $sampleName in designtable of section $section";
        my $replicate = $entryMap->{Replicate} or die "Define Replicate for $sampleName in designtable of section $section";
        my $peakFile  = $peaksfiles->{$sampleName}->[0];

        my $sampleId   = $treatments->{$sampleName}->[0];
        my $bamReads   = $bamfiles->{$sampleId}[0];
        my $controlId  = "";
        my $bamControl = "";

        if ( defined $controls ) {
          $controlId  = $controls->{$sampleName}->[0];
          $bamControl = $bamfiles->{$controlId}[0];
        }

        print $map $sampleId . "\t"
          . $tissue . "\t"
          . $factor . "\t"
          . $condition . "\t"
          . $replicate . "\t"
          . $bamReads . "\t"
          . $controlId . "\t"
          . $bamControl . "\t"
          . $peakFile . "\t"
          . $peakSoftware . "\n";
      }
      close($map);

      $result->{$name} = $mapfile;
    }
  }

  return $result;
}

sub getSequenceTaskClassname{
  my $cluster = shift;
  my $result = $cluster eq "slurm"?"CQS::SequenceTaskSlurm":"CQS::SequenceTask";
  return($result);
}


1;
