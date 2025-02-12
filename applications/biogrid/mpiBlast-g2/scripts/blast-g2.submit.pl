#!/usr/bin/perl
#-----------------------------------------------------------#
# Gridified MPI BLASTALL jobs on pragma                     #
#                                                           #
# Requirements;                                             #
#  1. Globus ToolKits >= 2.2                                #
#  2. MPICH-G2 == 1.2.5                                     #
#  3. mpiBlast >= 1.2.1                                     #
#                                                           #
# Language: Perl                                            #
# Author: Hurng-Chun Lee                                    #
# Date: 2004/10/16                                          #
#-----------------------------------------------------------#
use Cwd;
use Getopt::Std;
use Getopt::Long;
use Pod::Usage;

use FileHandle;

# !! The main program started here !!
# parsing the command line options
parseOpt();
my $query   = $opts{'qry'};
my $program = $opts{'prog'};
my $dbname  = $opts{'dbname'};
my $mfile   = $opts{'mfile'};

# Configure job
my %sysConf   = sysConfigure($mfile);
my %blastConf = blastConfigure($query,$program,$dbname);

my $rsl = genGlobusRSL(\%sysConf,\%blastConf);

my @rslClause = genGlobusRSLClause(\%sysConf,\%blastConf);

if($debug) {
    print "\n\nThe Generated RSL\n".$rsl."\n\n";
}

# !! rsl clause is only for globus-job-xxx command !!
#    foreach $rsl_clause (@rslClause) {
#        print "\n\nThe Generated RSL Clause\n".$rsl_clause."\n\n";
#    }
#}

# save rsl to local working directory for temporary use
open RSL,"> mpiblast-g2.rsl";
print RSL $rsl;
close(RSL);

# run your program via globusrun or mpirun
globusRun("mpiblast-g2.rsl");

# run your program via globus-job-submit
# !! Batch mode for multi-request job is not yet supported in GT2 !!
#globusBatchRun(\@rslClause,\%sysConf,\%blastConf);

# !! End of main program !!

#---------------------
# Subroutines
#---------------------
sub sysConfigure() {

    use Sys::Hostname;

    my $mfile = shift;
    my $host  = hostname();
    my %sysConf;

    $sysConf{'WDIR'}     = getcwd();
    $sysConf{'WDIR_URL'} = "gsiftp://$host/".$sysConf{'WDIR'};

    # Get machine list (return the reference to array
    #print $mfile."\n";
    my ($gatekeepers,$gk_no_nodes) = getGatekeepers($mfile);

    $sysConf{'GATEKEEPERS'}      = $gatekeepers;
    $sysConf{'GATEKEEPER_NODES'} = $gk_no_nodes;

    return %sysConf;
}

sub blastConfigure() {

    my ($query,$program,$dbname) = @_;

    my %blastConf;
    #$BLAST_HOME="TEMP_BLAST_HOME"; 
    $BLAST_HOME = $ENV{'BLASTG2_LOCATION'};
#    $LD_LIBRARY_PATH = $ENV{'LD_LIBRARY_PATH'};
    $blastConf{'BLAST_HOME'}  = '"'.$BLAST_HOME.'"';
    $blastConf{'BLAST_EXEC'}  = "\"".$BLAST_HOME.'/bin/mpiblast-g2'."\"";
    $blastConf{'BLAST_CONF'}  = $BLAST_HOME.'/etc/mpiblast-gasscopy.conf';
    $blastConf{'BLAST_PROF'}    = "BLAST_".$dbname.".prof";
    $blastConf{'BLAST_OUTPUT'}  = "BLAST_".$dbname.".out";
    $blastConf{'BLAST_QUERY'}   = $query;
    $blastConf{'BLAST_PROGRAM'} = $program;
    $blastConf{'BLAST_DBNAME'}  = $dbname;

    return %blastConf;
}

sub parseOpt() {
    my $args = $#ARGV;

    $ckopt = GetOptions('query=s'       => \$opts{'qry'},
                        'program=s'     => \$opts{'prog'},
                        'database=s'    => \$opts{'dbname'},
                        'machinefile=s' => \$opts{'mfile'},
                        'debug'         => \$debug,
                        'prof'          => \$prof,
                        'compressio'    => \$compressio,
                        'mpidb'         => \$mpidb,
                        'html'          => \$html,
#                        'pragma'        => \$pragma,
                        'man'           => \$man,
                        'help|?'        => \$fmtHelp);

    if ($man) {
        pod2usage(-exitval=>1,-verbose=>2);
    }

    # force -i and -b to be specified
    if( ! $opts{'qry'}    || ! $opts{'prog'} ||
        ! $opts{'dbname'} || ! $opts{'mfile'}) { $ckopt = 0; }


    if (! $ckopt || $fmtHelp || $args < 0) {
        pod2usage(-exitval=>2,-verbose=>0);
    }
}

sub getGatekeepers {
                                                                                
    my $mpi_machinefile = shift;
                                                                                
    my @gatekeepers = ();
    my @gk_no_nodes = ();
                                                                                
    open(FP,"< $mpi_machinefile") or die "Error: $!";
                                                                                
    while(<FP>) {

       chomp($_);

       $_ =~ s/^\s+//; # deleting leading spaces
       $_ =~ s/\s+$//; # deleting tailing spaces

       if( ! m/^#/ && $_ ne '') {

          my @data = split(/[\s]+/,$_);
          $data[0] =~ s/\"//g;
          push(@gatekeepers,$data[0]);
          push(@gk_no_nodes,$data[1]);

       }
    }
                                                                                
    return (\@gatekeepers,\@gk_no_nodes);
}
#-------------------------------------
# Generating Globus RSL Clause String
#-------------------------------------
sub genGlobusRSLClause {

    my ($sysConf_ref,$blastConf_ref) = @_;

    my %sysConf   = %$sysConf_ref;
    my %blastConf = %$blastConf_ref;

    my @rslClause;

    # Compose Executable arguments
    # The --config-file generator need to be reorganized
    my $arg_val = "\"--config-file=".$blastConf{'BLAST_CONF'}."\" ";
       if($prof) { $arg_val.= "\"--pro-phile=".$blastConf{'BLAST_PROF'}."\" "; }       $arg_val.= "\"--wdir-url=".$sysConf{'WDIR_URL'}."\" ";
       $arg_val.= "\"--removedb\" ";
                                                                                
       if($debug) { $arg_val.= "\"--debug\" "; }
       if($compressio) { $arg_val.= "\"--compress-io\" "; }
       if(! $mpidb) { $arg_val.= "\"--disable-mpi-db\" "; }

       $arg_val.= "\"-p\" \"".$blastConf{'BLAST_PROGRAM'}."\" ";
       $arg_val.= "\"-d\" \"".$blastConf{'BLAST_DBNAME'}."\" ";
       $arg_val.= "\"-i\" \"".$blastConf{'BLAST_QUERY'}."\" ";
       $arg_val.= "\"-o\" \"".$blastConf{'BLAST_OUTPUT'}."\" ";

       if($html) { $arg_val.= "\"-T\" \"T\""; }

    my $gk_count = 0;
    my $env_val;
    foreach $gk (@{$sysConf{'GATEKEEPERS'}}) {
    $env_val = "(GLOBUS_DUROC_SUBJOB_INDEX $gk_count)(LD_LIBRARY_PATH \$(GLOBUS_LOCATION)#\"/lib\")";
#    if( $pragma ) {
## Extra configuration for ume.hpcc.jp
#      if($gk =~ /ume\.hpcc\.jp/) {
#         $env_val = "(GLOBUS_DUROC_SUBJOB_INDEX $gk_count)(LD_LIBRARY_PATH \$(GLOBUS_LOCATION)#\"/lib:/usr/local/GCC/redhat73/3.2.2/lib\")";
#      }
#      else {
#         $env_val = "(GLOBUS_DUROC_SUBJOB_INDEX $gk_count)(LD_LIBRARY_PATH \$(GLOBUS_LOCATION)#\"/lib\")";
#      }
## Extra configuration for pragma sites
#    }
#    else {
#      $env_val = "(GLOBUS_DUROC_SUBJOB_INDEX $gk_count)(LD_LIBRARY_PATH \$(GLOBUS_LOCATION)#\"/lib\")";
#    }
 
        # Composing RSL script
        $rslClause[$gk_count] = "";

        # !! count,label and executable are not necessary in rsl clause !!
        #addRSLAttr(\$rslClause[$gk_count],"count",@{$sysConf{'GATEKEEPER_NODES'}}[$gk_count]);
        #addRSLAttr(\$rslClause[$gk_count],"label","\"subjob $gk_count\"");
        #addRSLAttr(\$rslClause[$gk_count],"executable",$blastConf{'BLAST_EXEC'});
        addRSLAttr(\$rslClause[$gk_count],"environment",$env_val);
        if($gk_count != 0) {
          addRSLAttr(\$rslClause[$gk_count],"directory","\$(HOME)");
        }else{
          addRSLAttr(\$rslClause[$gk_count],"directory","\"$sysConf{'WDIR'}\"");        }
        if($debug) {
          if($gk_count != 0) {
            addRSLAttr(\$rslClause[$gk_count],"stdout","\$(HOME)/stdout.".$gk_count."\"");
            addRSLAttr(\$rslClause[$gk_count],"stderr","\$(HOME)/stderr.".$gk_count."\"");
          }else{
            addRSLAttr(\$rslClause[$gk_count],"stdout","\"$sysConf{'WDIR'}/stdout.".$gk_count."\"");
            addRSLAttr(\$rslClause[$gk_count],"stderr","\"$sysConf{'WDIR'}/stderr.".$gk_count."\"");
          }
        }
        addRSLAttr(\$rslClause[$gk_count],"arguments",$arg_val);

        $gk_count++;
    }

    return @rslClause;
}

#-----------------------
# Generating Globus RSL
#-----------------------
sub genGlobusRSL {

    my ($sysConf_ref,$blastConf_ref) = @_;

    my %sysConf   = %$sysConf_ref;
    my %blastConf = %$blastConf_ref;

    # Compose Executable arguments
    # The --config-file generator need to be reorganized
    my $arg_val = "\"--config-file=".$blastConf{'BLAST_CONF'}."\" ";
       if($prof) { $arg_val.= "\"--pro-phile=".$blastConf{'BLAST_PROF'}."\" "; }
       $arg_val.= "\"--wdir-url=".$sysConf{'WDIR_URL'}."\" ";
       $arg_val.= "\"--removedb\" ";

       if($debug) { $arg_val.= "\"--debug\" "; }
       if($compressio) { $arg_val.= "\"--compress-io\" "; }
       if(! $mpidb) { $arg_val.= "\"--disable-mpi-db\" "; }

       $arg_val.= "\"-p\" \"".$blastConf{'BLAST_PROGRAM'}."\" ";
       $arg_val.= "\"-d\" \"".$blastConf{'BLAST_DBNAME'}."\" ";
       $arg_val.= "\"-i\" \"".$blastConf{'BLAST_QUERY'}."\" ";
       $arg_val.= "\"-o\" \"".$blastConf{'BLAST_OUTPUT'}."\" ";
       if($html) { $arg_val.= "\"-T\" \"T\""; }

    my $gk_count = 0;
    my $rsl = '+';
    my $env_val;
    foreach $gk (@{$sysConf{'GATEKEEPERS'}}) {
    $env_val = "(GLOBUS_DUROC_SUBJOB_INDEX $gk_count)(LD_LIBRARY_PATH \$(GLOBUS_LOCATION)#\"/lib\")";
#    if( $pragma ) {
## Extra configuration for ume.hpcc.jp
#      if($gk =~ /ume\.hpcc\.jp/) {
#         $env_val = "(GLOBUS_DUROC_SUBJOB_INDEX $gk_count)(LD_LIBRARY_PATH \$(GLOBUS_LOCATION)#\"/lib:/usr/local/GCC/redhat73/3.2.2/lib\")";
#      }
#      else {
#         $env_val = "(GLOBUS_DUROC_SUBJOB_INDEX $gk_count)(LD_LIBRARY_PATH \$(GLOBUS_LOCATION)#\"/lib\")";
#      }
## Extra configuration for pragma sites
#    }
#    else {
#      $env_val = "(GLOBUS_DUROC_SUBJOB_INDEX $gk_count)(LD_LIBRARY_PATH \$(GLOBUS_LOCATION)#\"/lib\")";
#    }

        # Composing RSL script
        $rsl .= '(&';
        addRSLAttr(\$rsl,"resourceManagerContact",$gk);
        addRSLAttr(\$rsl,"count",@{$sysConf{'GATEKEEPER_NODES'}}[$gk_count]);
        addRSLAttr(\$rsl,"label","\"subjob $gk_count\"");
        addRSLAttr(\$rsl,"environment",$env_val);
        if($gk_count != 0) {
          addRSLAttr(\$rsl,"directory","\$(HOME)");
        }else{
          addRSLAttr(\$rsl,"directory","\"$sysConf{'WDIR'}\"");
        }
                                                                                
        if($debug) {
          if($gk_count != 0) {
            addRSLAttr(\$rsl,"stdout","\$(HOME)/stdout.".$gk_count."\"");
            addRSLAttr(\$rsl,"stderr","\$(HOME)/stderr.".$gk_count."\"");
          }else{
            addRSLAttr(\$rsl,"stdout","\"$sysConf{'WDIR'}/stdout.".$gk_count."\"");
            addRSLAttr(\$rsl,"stderr","\"$sysConf{'WDIR'}/stderr.".$gk_count."\"");
          }
        }
        addRSLAttr(\$rsl,"executable",$blastConf{'BLAST_EXEC'});
        addRSLAttr(\$rsl,"arguments",$arg_val);
        $rsl .= ')';

        $gk_count++;
    }
    return $rsl;
}

#-----------------------
# Adding RSL Attribute 
#-----------------------
sub addRSLAttr {

    my ($rsl_ref,$rsl_key,$rsl_val) = @_;

    $$rsl_ref .= "(".$rsl_key."=".$rsl_val.")"; 
}

#-----------------------------
# Using mpirun to run the job 
#-----------------------------
sub mpiRun {

    my $rsl_file = shift;
    my $cmd = "mpirun -globusrsl $rsl_file";

    if($debug) {print "JobRun Command: $cmd\n";}

    my $fp = FileHandle->new;
    my $pid  = open($fp,$cmd." |");   # Pipeout the standard output
    if( $pid ) {

        my $pidFp = FileHandle->new;
        open($pidFp,"> pid");
        print $pidFp "$pid\n";
        close($pidFp);

        waitpid($pid,0);
        while( my $line=<$fp> ) {
            if($debug) {print "$line";}
        }
    }
    close($fp);
}

#-----------------------------
# Using globusrun to run the job 
#-----------------------------
sub globusRun {

    my $rsl_file = shift;
    my $cmd = "globusrun -mpirun 1 -w -s -f $rsl_file";

    if($debug) {print "JobRun Command:\n$cmd\n";}

    my $fp = FileHandle->new;
    my $pid  = open($fp,$cmd." |");   # Pipeout the standard output
    if( $pid ) {

        my $pidFp = FileHandle->new;
        open($pidFp,"> pid");
        print $pidFp "$pid\n";
        close($pidFp);

        waitpid($pid,0);
        while( my $line=<$fp> ) {
            if($debug) {print "$line";}
        }
    }
    close($fp);
}

#------------------------------
# Using globus-job-submit
#------------------------------
sub globusBatchRun {

    my ($rslClause_ref,$sysConf_ref,$blastConf_ref) = @_;

    my @rslClause = @$rslClause_ref;
    my %sysConf   = %$sysConf_ref;
    my %blastConf = %$blastConf_ref;

    my $cmd = "globus-job-run";

    #if($debug) { $cmd.= " -dumprsl "; }

    my $gk_count = 0;
    my $rsl = '+';
    foreach $gk (@{$sysConf{'GATEKEEPERS'}}) {

       $cmd.=' -: '.$gk.' -np '.@{$sysConf{'GATEKEEPER_NODES'}}[$gk_count];
       $cmd.=' -x '."'".$rslClause[$gk_count]."'";
       $cmd.=' '."'".$blastConf{'BLAST_EXEC'}."'";

       $gk_count++;
    }

    if($debug) {print "JobRun Command:\n$cmd\n";}

    my $fp = FileHandle->new;
    my $pid  = open($fp,$cmd." |");   # Pipeout the standard output
    if( $pid ) {

        my $pidFp = FileHandle->new;
        open($pidFp,"> pid");
        print $pidFp "$pid\n";
        close($pidFp);

        waitpid($pid,0);
        while( my $line=<$fp> ) {
            if($debug) {print "$line";}
        }
    }
    close($fp);
}

#------------------------------
# Subroutine for getting output
# (through globus-url-copy
#------------------------------
sub getOutput {
    
}

__END__

=head1 NAME
                                                                                
blast-g2.submit - Tool for running mpiblast-g2 program 

=head1 DESCRIPTION
                                                                                
=head1 SYNOPSIS
                                                                                
blast-g2.submit [options]
                                                                                
 Options:
   -help        brief help message
   -man         full documentation
   -html        enable html output 
   -debug       enable debuging mode 
   -prof        enable prof file
   -compressio  enable transferring compressed db fragments
   -mpidb       enable fetching remote sequence information
#   -pragma      enable customization for pragma testbed 
   -program     *prog*   specify the program name of blastall 
   -query       *qry*    specify the filename of input queries 
   -database    *dbname* specify the name of target database
   -machinefile *mfile*  specify the machinefile for mpich-g2 
                                                                                
=head1 OPTIONS

=item B<-help>
                                                                                
Print a brief help message and exits.
                                                                                
=item B<-man>
                                                                                
Print a full manual.
                                                                                
=item B<-debug>
                                                                                
Enable debug mode. Debug messages will be displayed.

=item B<-html>
                                                                                
Enable html output mode. Blast report will be in html format.

=item B<-compressio>
                                                                                
Transferring tgz compressed db fragments. (Faster)

=item B<-mpidb>
                                                                                
Using MPI to fetch remote database sequence information. (Slow but scalable)

=item B<-pragma>
                                                                                
#Customization function for pragma testbed.

=item B<-program> I<prog>
                                                                                
=item B<-query> I<qry>
                                                                                
=item B<-database> I<dbname>
                                                                                
=item B<-machinefile> I<mfile>

=head1 AUTHOR

Hurng-Chun Lee <hclee@gate.sinica.edu.tw>
