#!/usr/bin/perl
package Proteomics::Summary::AccumulateBuildSummary;

use strict;
use warnings;
use File::Basename;
use File::Slurp;
use CQS::PBS;
use CQS::ConfigUtils;
use CQS::SystemUtils;
use CQS::FileUtils;
use CQS::Task;
use CQS::StringUtils;

our @ISA = qw(Proteomics::Summary::AbstractBuildSummary);

sub new {
  my ($class) = @_;
  my $self = $class->SUPER::new();
  $self->{_name}   = "Proteomics::Summary::AccumulateBuildSummary";
  $self->{_suffix} = "_abs";
  bless $self, $class;
  return $self;
}

sub perform {
  my ( $self, $config, $section ) = @_;

  my ( $task_name, $path_file, $pbsDesc, $target_dir, $logDir, $pbsDir, $resultDir, $option, $sh_direct, $cluster, $thread, $memory ) = get_parameter( $config, $section );

  $self->{_task_prefix} = get_option( $config, $section, "prefix", "" );
  $self->{_task_suffix} = get_option( $config, $section, "suffix", "" );

  my $proteomicstools = get_param_file( $config->{$section}{proteomicstools}, "proteomicstools", 1 );

  my $bin_size = get_option( $config, $section, "bin_size", 10 );
  my $bins     = $config->{$section}{"bins"};
  my @bins     = ();
  if ( defined $bins ) {
    @bins = @{$bins};
  }

  my ( $datasets, $lines, $dataset ) = get_datasets( $config, $section );
  my %datasets = %{$datasets};
  my @lines    = @{$lines};
  my @dataset  = @{$dataset};

  my $shfile = $self->taskfile( $pbsDir, $task_name );
  open( SH, ">$shfile" ) or die "Cannot create $shfile";
  print SH get_run_command($sh_direct) . "\n";

  my @sampleNames     = sort keys %datasets;
  my $sampleNameCount = scalar(@sampleNames);
  my $numlen          = length($sampleNameCount);

  my $index      = 0;
  my $sampleSize = 0;

  while ( $sampleSize <= $sampleNameCount ) {
    if ( $index < scalar(@bins) ) {
      $sampleSize = $bins[$index];
      $index++;
    }
    else {
      $sampleSize += $bin_size;
    }
    if ( $sampleSize > $sampleNameCount ) {
      $sampleSize = $sampleNameCount;
    }
    my $currentTaskName = sprintf( "${task_name}_%0${numlen}d", $sampleSize );

    my $currentParamFile = $resultDir . "/" . $currentTaskName . ".param";
    open( OUT, ">$currentParamFile" ) or die $!;

    for ( my $index = 0 ; $index < scalar(@lines) ; $index++ ) {
      print OUT $lines[$index] . "\n";
      if ( $lines[$index] =~ "<Datasets>" ) {
        last;
      }
    }
    for ( my $index = 0 ; $index < $sampleSize ; $index++ ) {
      my $sampleName = $sampleNames[$index];
      print OUT "    <Dataset>\n";
      print OUT "      <Name>$sampleName</Name>\n";
      foreach my $dsline (@dataset) {
        print OUT $dsline . "\n";
      }
      print OUT "      <PathNames>\n";
      my @sampleFiles = @{ $datasets{$sampleName} };
      for my $sampleFile (@sampleFiles) {
        print OUT "        <PathName>$sampleFile</PathName>\n";
      }
      print OUT "      </PathNames>\n";
      print OUT "    </Dataset>\n";
    }

    for ( my $index = 0 ; $index < scalar(@lines) ; $index++ ) {
      if ( $lines[$index] =~ "</Datasets>" ) {
        for ( my $nextindex = $index ; $nextindex < scalar(@lines) ; $nextindex++ ) {
          print OUT $lines[$nextindex] . "\n";
        }
        last;
      }
    }

    close(OUT);

    my $pbsFile = $self->pbsfile( $pbsDir, $currentTaskName );
    my $pbsName = basename($pbsFile);
    my $log     = $self->logfile( $logDir, $currentTaskName );

    print SH "\$MYCMD ./$pbsName \n";

    my $log_desc = $cluster->get_log_desc($log);

    my $resultFile = $resultDir . "/" . $currentTaskName . ".noredundant";

    open( OUT, ">$pbsFile" ) or die $!;
    print OUT "$pbsDesc
$log_desc

$path_file

cd $resultDir

echo buildsummary=`date`

if [ ! -s $resultFile ]; then
  mono $proteomicstools buildsummary -i $currentParamFile 
fi

echo finished=`date`

exit 0 
";
    close OUT;
    print "$pbsFile created \n";

    if ( $sampleSize == scalar(@sampleNames) ) {
      last;
    }
  }

  close(SH);

  if ( is_linux() ) {
    chmod 0755, $shfile;
  }

  print "!!!shell file $shfile created, you can run this shell file to submit all ", $self->{_name}, " tasks.\n";
}

sub result {
  my ( $self, $config, $section, $pattern ) = @_;

  my ( $task_name, $path_file, $pbsDesc, $target_dir, $logDir, $pbsDir, $resultDir, $option, $sh_direct ) = get_parameter( $config, $section );

  my $bin_size = get_option( $config, $section, "bin_size", 10 );
  my $bins     = $config->{$section}{"bins"};
  my @bins     = ();
  if ( defined $bins ) {
    @bins = @{$bins};
  }

  my %rawFiles = %{ get_raw_files( $config, $section ) };

  my $result      = {};
  my @resultFiles = ();

  my $sampleNameCount = scalar( keys %rawFiles );
  my $numlen          = length($sampleNameCount);

  my $index      = 0;
  my $sampleSize = 0;

  while ( $sampleSize <= $sampleNameCount ) {
    if ( $index < scalar(@bins) ) {
      $sampleSize = $bins[$index];
      $index++;
    }
    else {
      $sampleSize += $bin_size;
    }
    if ( $sampleSize > $sampleNameCount ) {
      $sampleSize = $sampleNameCount;
    }
    my $currentTaskName = sprintf( "${task_name}_%0${numlen}d", $sampleSize );

    my $currentNoredundantFile = $resultDir . "/" . $currentTaskName . ".noredundant";
    push( @resultFiles, $currentNoredundantFile );

    if ( $sampleSize == $sampleNameCount ) {
      last;
    }

    $sampleSize += $bin_size;
    if ( $sampleSize > $sampleNameCount ) {
      $sampleSize = $sampleNameCount;
    }
  }
  $result->{$task_name} = filter_array( \@resultFiles, $pattern );
  return $result;
}
1;
