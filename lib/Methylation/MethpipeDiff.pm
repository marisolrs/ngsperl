#!/usr/bin/perl
package Methylation::MethpipeDiff;

use strict;
use warnings;
use File::Basename;
use CQS::PBS;
use CQS::ConfigUtils;
use CQS::SystemUtils;
use CQS::FileUtils;
use CQS::Task;
use CQS::GroupTask;
use CQS::NGSCommon;
use CQS::StringUtils;

our @ISA = qw(CQS::GroupTask);

sub new {
  my ($class) = @_;
  my $self = $class->SUPER::new();
  $self->{_name}   = __PACKAGE__;
  $self->{_suffix} = "_methdiff";
  bless $self, $class;
  return $self;
}

sub perform {
  my ( $self, $config, $section ) = @_;

  my ( $task_name, $path_file, $pbs_desc, $target_dir, $log_dir, $pbs_dir, $result_dir, $option, $sh_direct, $cluster ) = get_parameter( $config, $section );

  my $comparisons = get_raw_files( $config, $section, "comparison" );
  my @comparison_names = keys %{$comparisons};

  my $methfiles = get_raw_files( $config, $section, "methfile" );
  my $hmrfiles = get_raw_files( $config, $section, "hmrfile" );

  my $shfile = $self->get_task_filename( $pbs_dir, $task_name );
  open( my $sh, ">$shfile" ) or die "Cannot create $shfile";
  print $sh get_run_command($sh_direct) . "\n";
  print $sh "cd $pbs_dir\n";

  for my $group_name (@comparison_names) {
    my @sampleNames = @{ $comparisons->{$group_name}; };
    my $sampleCount = scalar(@sampleNames);

    if ( $sampleCount != 2 ) {
      die "SampleFile should be 2 paired samples.";
    }

    my $cur_dir = create_directory_or_die( $result_dir . "/$group_name" );

    my $controlMethFile   = ${$methfiles->{ $sampleNames[0] }}[0];
    my $treatmentMethFile = ${$methfiles->{ $sampleNames[1] }}[0];
    my $methdiffFile      = "${group_name}.methdiff";
    my $controlHmrFile   = ${$hmrfiles->{ $sampleNames[0] }}[0];
    my $treatmentHmrFile = ${$hmrfiles->{ $sampleNames[1] }}[0];
    my $dmrFile1      = basename($controlHmrFile).".DMR";
    my $dmrFile2      = basename($treatmentHmrFile).".DMR";
    
    my $pbs_file = $self->get_pbs_filename( $pbs_dir, $group_name );
    my $pbs_name = basename($pbs_file);
    my $log = $self->get_log_filename( $log_dir, $group_name );

    print $sh "\$MYCMD ./$pbs_name \n";

    my $log_desc = $cluster->get_log_description($log);

    my $pbs = $self->open_pbs( $pbs_file, $pbs_desc, $log_desc, $path_file, $cur_dir );

    print $pbs "
if [ ! -s $methdiffFile ]; then
  echo methdiff=`date`
  methdiff -o $methdiffFile $controlMethFile $treatmentMethFile
fi
if [[ ! -s $dmrFile1 || ! -s $dmrFile2 ]]; then
  echo dmr=`date`
  dmr $methdiffFile $controlHmrFile $treatmentHmrFile $dmrFile1 $dmrFile2
fi
";
    $self->close_pbs( $pbs, $pbs_file );
  }

  close $sh;

  if ( is_linux() ) {
    chmod 0755, $shfile;
  }

  print "!!!shell file $shfile created, you can run this shell file to submit all MethpipeDiff tasks.\n";
}

sub result {
  my ( $self, $config, $section, $pattern ) = @_;

  my ( $task_name, $path_file, $pbs_desc, $target_dir, $log_dir, $pbs_dir, $result_dir, $option, $sh_direct ) = get_parameter( $config, $section, 0 );

  my $comparisons = get_raw_files( $config, $section, "comparison" );

  my $result = {};
  for my $group_name ( keys %{$comparisons} ) {
    my @result_files = ();
    my $cur_dir      = $result_dir . "/$group_name";
    push( @result_files, "$cur_dir/${group_name}.methdiff" );
    
    my @sampleNames = @{ $comparisons->{$group_name}; };
    my $controlHmrFile=$sampleNames[0].".mr.hmr.DMR";
    my $treatmentHmrFile=$sampleNames[1].".mr.hmr.DMR";
    push( @result_files, "$cur_dir/${controlHmrFile}" );
    push( @result_files, "$cur_dir/${treatmentHmrFile}" );
    $result->{$group_name} = filter_array( \@result_files, $pattern );
  }
  return $result;
}

1;
