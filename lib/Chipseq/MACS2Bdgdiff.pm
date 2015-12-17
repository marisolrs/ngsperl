#!/usr/bin/perl
package Chipseq::MACS2Bdgdiff;

use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use CQS::PBS;
use CQS::ConfigUtils;
use CQS::SystemUtils;
use CQS::FileUtils;
use CQS::NGSCommon;
use CQS::GroupTask;
use CQS::StringUtils;

our @ISA = qw(CQS::GroupTask);

my $directory;

sub new {
  my ($class) = @_;
  my $self = $class->SUPER::new();
  $self->{_name}   = "Chipseq::MACS2Bdgdiff";
  $self->{_suffix} = "_mb";
  bless $self, $class;
  return $self;
}

sub perform {
  my ( $self, $config, $section ) = @_;

  my ( $task_name, $path_file, $pbsDesc, $target_dir, $logDir, $pbsDir, $resultDir, $option, $sh_direct, $cluster ) = get_parameter( $config, $section );

  my %group_sample_map = %{ $self->get_group_sample_map( $config, $section ) };
  
  print Dumper( %group_sample_map);
  
  my $comparisons = get_raw_files( $config, $section, "pairs" );
  my $totalPair = scalar( keys %{$comparisons} );
  if ( 0 == $totalPair ) {
    die "No pair defined!";
  }

  my $shfile = $self->taskfile( $pbsDir, $task_name );
  open( SH, ">$shfile" ) or die "Cannot create $shfile";
  print SH get_run_command($sh_direct);

  for my $comparisonName ( sort keys %{$comparisons} ) {
    my @groupNames = @{ $comparisons->{$comparisonName} };
    my $groupCount = scalar(@groupNames);
    if ( $groupCount != 2 ) {
      die "Comparison should be control,treatment paired.";
    }

    my @condition1        = @{ $group_sample_map{ $groupNames[0] } };
    my $condition1treat   = join(" ", @{filter_array( \@condition1, "_treat_pileup.bdg" )});
    my $condition1control = join(" ", @{filter_array( \@condition1, "_control_lambda.bdg" )});

    my @condition2        = @{ $group_sample_map{ $groupNames[1] } };
    my $condition2treat   = join(" ", @{filter_array( \@condition2, "_treat_pileup.bdg" )});
    my $condition2control = join(" ", @{filter_array( \@condition2, "_control_lambda.bdg" )});

    my $curDir = create_directory_or_die( $resultDir . "/$comparisonName" );

    my $pbsFile = $self->pbsfile( $pbsDir, $comparisonName );
    my $pbsName = basename($pbsFile);
    my $log     = $self->logfile( $logDir, $comparisonName );

    print SH "\$MYCMD ./$pbsName \n";

    my $log_desc = $cluster->get_log_desc($log);

    my $final = "";

    open( OUT, ">$pbsFile" ) or die $!;
    print OUT "$pbsDesc
$log_desc

$path_file 

echo macs2_bdgdiff=`date` 

cd $curDir

if [ ! -s $final ]; then
  macs2 bdgdiff $option --t1 $condition1treat --t2 $condition2treat --c1 $condition1control --c2 $condition2control --o-prefix $comparisonName  
fi

echo finished=`date`
";
    close OUT;

    print "$pbsFile created \n";

    print SH "\$MYCMD ./$pbsName \n";
  }

  close(SH);

  if ( is_linux() ) {
    chmod 0755, $shfile;
  }

  print "!!!shell file $shfile created, you can run this shell file to submit all " . $self->{_name} . " tasks.\n";
}

sub result {
  my ( $self, $config, $section, $pattern ) = @_;

  my ( $task_name, $path_file, $pbsDesc, $target_dir, $logDir, $pbsDir, $resultDir, $option, $sh_direct ) = get_parameter( $config, $section );

  my $comparisons = get_raw_files( $config, $section, "pairs" );
  my $result = {};
  for my $comparisonName ( sort keys %{$comparisons} ) {
    my @resultFiles = ();
    push( @resultFiles, $resultDir . "/${comparisonName}.csv" );
    $result->{$comparisonName} = filter_array( \@resultFiles, $pattern );
  }
  return $result;
}

1;
