#!/urs/bin/perl

package SV_parser;
use strict;
use warnings;

use 5.18.2;

use feature qw/ say /;
use Data::Dumper;

sub typer {
	my $file = shift;
	my $type;
	if (`grep "source=LUMPY" $file`){
		say "Recognised $file as Lumpy input";
		$type = 'lumpy';
		parse($file, $type);
	}
	
	elsif (`grep "DELLY" $file`){
		say "Recognised $file as Delly input";
		$type = 'delly';
		parse($file, $type);
	}
	elsif (`grep "VarScan" $file`){
		say "Recognised $file as VarScan2 input";
		$type = 'varscan2';
		parse($file, $type);
	}
	
	elsif (`grep "bamsurgeon spike-in" $file`){
		say "Recognised $file as novoBreak input";
		$type = 'novobreak';
		parse($file, $type);
	}
	
	else {
		die "This VCF is not from lumpy or delly. Abort";
	}
}

sub parse {
	my ($file, $type) = @_;
	open my $in, '<', $file or die $!;

	my @headers;
	
	my (%SVs, %info, %filtered_SVs);
	
	my ($tumour_name, $control_name);
	
	my %format_long;

	my %info_long;
	my $filter_count;

	my @samples;
	
	while(<$in>){
		chomp;

		if (/^#{2}/){
	 		push @headers, $_;
			$filtered_SVs{$.} = $_;

			if (/##FORMAT/){
				
				my ($format_long) = $_ =~ /\"(.*?)\"/;
				my ($available_format_info) = $_ =~ /ID=(.*?),/;
				$format_long{$available_format_info} = $format_long;
			}

			if (/##INFO/) {
				my ($info_long) = $_ =~ /\"(.*?)\"/;
				my ($available_info) = $_ =~ /ID=(.*?),/;
				$info_long{$available_info} = $info_long;
			}
			next;
		}

		if (/^#{1}/){
	 		push @headers, $_;
			$filtered_SVs{$.} = $_;
			my @split = split;
			push @samples, $_ foreach @split[9..$#split];
 			
			$tumour_name = $samples[0];
			$control_name = $samples[1];
			next;
		}

		my @fields = split;
				
	    my ($chr, $start, $id, $ref, $alt, $quality_score, $filt, $info_block, $format_block, @sample_info) = @fields;
		
		if ($id eq 'N' or $id eq '.'){
			$id = $.;
		}
		
 		my %sample_parts;

 		push @{$sample_parts{$samples[$_]}}, split(/:/, $sample_info[$_]) for 0..$#samples;
		
		my @tumour_parts 	= split(/:/, $sample_info[0]);
	    my @normal_parts 	= split(/:/, $sample_info[1]);
						
		my @format 		 	= split(/:/, $format_block);
		my @info_parts		= split(/;/, $info_block);
		
		my %sample_info;
		
		for my $sample (@samples){

			for my $info (0..$#format){
				$sample_info{$id}{$sample}{$format[$info]} = $sample_parts{$sample}[$info];
			}
			
		}
										
 		my @normals = @samples[1..$#samples];
		
		my @filter_reasons;
		
		###################
		# Genotype filter #
		###################
		
		# Filter if ANY of the controls are NOT 'GT = 0/0' (hom ref) 
		
		for my $normal (@normals){
			if ($sample_info{$id}{$normal}{'GT'} eq '1/1' or $sample_info{$id}{$normal}{'GT'} eq '0/1'){
				push @filter_reasons, "$normal\_not_homo_ref=" . $sample_info{$id}{$normal}{'GT'};
			}
		}
		
		###################
		
		my %information;
						
		foreach(@info_parts){
			
			my ($info_key, $info_value);

			if (/=/){
				($info_key, $info_value) = $_ =~ /(.*)=(.*)/;
			}

			else {
				($info_key) = $_ =~ /(.*)/;
				$info_value = "TRUE";
			}
			$information{$id}{$info_key} = $info_value;
		}
						
	    my ($SV_type) = $info_block =~ /SVTYPE=(.*?);/;
				
		my ($SV_length, $chr2, $stop, $t_SR, $t_PE, $filters);
		
		if ($type eq 'lumpy'){
			( $SV_length, $chr2, $stop, $t_SR, $t_PE, $filters ) = lumpy( $id, $info_block, $SV_type, $alt, $start, \%sample_info, $tumour_name, $control_name, \@samples, \@normals, \@filter_reasons );
		}
		
		elsif ($type eq 'delly'){
			( $SV_length, $chr2, $stop, $t_SR, $t_PE, $filters ) = delly( $info_block, $start, $SV_type, \@filter_reasons );
		}
		
		elsif ($type eq 'novobreak'){			
			( $SV_length, $chr2, $stop, $t_SR, $t_PE, $filters  ) = novobreak( $info_block, $start, $SV_type, \@filter_reasons );
		}
		
		$filters = chrom_filter( $chr, $chr2, $filters );
				
		$SVs{$id} = [ @fields[0..10], $SV_type, $SV_length, $stop, $chr2, $t_SR, $t_PE, $filters, \@samples ];

		$info{$id} = [ [@format], [%format_long], [%info_long], [@tumour_parts], [@normal_parts], [%information], [%sample_info] ];
		
		if (scalar @{$filters} == 0){
			$filtered_SVs{$.} = $_;
		}
			
	}	
	return (\%SVs, \%info, \%filtered_SVs);	
}


sub print_variants {
	
	my ( $SVs, $filtered_SVs, $name, $output_dir ) = @_;
	
	open my $out, '>', $output_dir . $name . ".filtered.vcf" or die $!;

	say "Writing output to " . "'$output_dir" . $name . ".filtered.vcf'";
		
	my %filtered_SVs = %{ $filtered_SVs };
	my $sv_count = 0;
	for (sort {$a <=> $b} keys %filtered_SVs){
		my $line = $filtered_SVs{$_};
				
		if ($line =~ /^#/){
			print $out $line . "\n"; 
		}
		else {
			$sv_count++;
			my @cols = split("\t", $line);
			print $out join("\t", @cols[0..5], "PASS", @cols[7..$#cols]) . "\n";
		}
	}	
	say "$sv_count variants passed all filters";
}

sub novobreak {
	my ($info_block, $start, $SV_type, $filters) = @_;
	
	my @filter_reasons = @{ $filters };
	
    my ($stop) = $info_block =~ /;END=(.*?);/;
		
	my ($SV_length) = ($stop - $start);
	
		my ($t_SR, $t_PE) = (0,0);
		
		if ($info_block =~ /;SR=(\d+);/){
	   		$t_SR = $1;
	   	}
	   
	   if ($info_block =~ /;PE=(\d+);/){
	   		$t_PE = $1;
	   }
 	  		
		if ($start > $stop){
			my $old_start = $start;
			my $old_stop = $stop;
			$start = $old_stop;
			$stop = $old_start;
		}
			
		my ($chr2) = $info_block =~ /CHR2=(.*?);/;
		
	return ($SV_length, $chr2, $stop, $t_SR, $t_PE, \@filter_reasons );
}

sub lumpy {
	my ( $id, $info_block, $SV_type, $alt, $start, $sample_info, $tumour, $control, $samples, $normals, $filters ) = @_;
	
	my @filter_reasons = @{ $filters };
	my @normals = @{ $normals };
	
	my @samples = @{ $samples };
	
	my %sample_info = %{ $sample_info };
		
		
	my ($SV_length) = $info_block =~ /SVLEN=(.*?);/;
	
			
		my ($t_PE, $t_SR, $all_c_PE, $all_c_SR, $c_PE, $c_SR) = (0,0,0,0,0,0);
		
		########################
		# Read support filters #
		########################
		
		# Get read support for tumour
		$t_PE = $sample_info{$id}{$tumour}{'PE'};
		$t_SR = $sample_info{$id}{$tumour}{'SR'};
		
		my $tumour_read_support = ( $t_PE + $t_SR );
		
		# Create temp pseudo counts to avoid illegal division by 0
		my $sc_tumour_read_support = $tumour_read_support + 0.001;
		
		# Anything with less than 4 supporting reads is filtered
		if ( $tumour_read_support < 4 ){
			push @filter_reasons, 'tumour_reads<4=' . $tumour_read_support;
		}
					
		# for precise variants:
		if ($info_block !~ /IMPRECISE;/){
						
			# We want to be strict, so include all controls used for genotyping (and sum read support)
			for my $normal (@normals){
				$sample_info{$id}{$normal}{'PE'} eq '.' ? $sample_info{$id}{$normal}{'PE'} = '0' : $all_c_PE += $sample_info{$id}{$normal}{'PE'};
				$sample_info{$id}{$normal}{'SR'} eq '.' ? $sample_info{$id}{$normal}{'SR'} = '0' : $all_c_SR += $sample_info{$id}{$normal}{'SR'};			
			}
	
			my $all_control_read_support = ( $all_c_PE + $all_c_SR );
						
			# Filter if # tumour reads supporting var is less than 5 * control reads
			# Or if there are more than 2 control reads
			if ( $all_control_read_support > 0 ){
				push @filter_reasons, 'precise_var_with_normal_read_support=' . $all_control_read_support;
			}
		}
		
		my $sc_direct_control_read_support = 0;
		# for imprecise variants:
		if ($info_block =~ /IMPRECISE;/){
						
			# Filter if # tumour reads supporting var is less than 5 * control reads
			# Or if there are more than 2 control reads
			
			# Get read support for direct control
			$c_PE =  $sample_info{$id}{$control}{'PE'};
			$c_SR =  $sample_info{$id}{$control}{'SR'};
	
			my $direct_control_read_support = ( $c_PE + $c_SR );
			$sc_direct_control_read_support = $direct_control_read_support + 0.001;
			
			if ( $direct_control_read_support > 1 ){
				push @filter_reasons, "imprecise_var_with_$control\_read_support>1=" . $direct_control_read_support;
			}
			
		}
		
		######################
		# Read depth filters #
		######################
				
		if ( exists $sample_info{$id}{$tumour}{'DP'} ){
			
			my $t_DP =  $sample_info{$id}{$tumour}{'DP'};
			my $c_DP =  $sample_info{$id}{$control}{'DP'};
			
			# Flag if either control or tumour has depth < 10 at site
			if ( $t_DP <= 10 ){
				push @filter_reasons, 'tumour_depth<10=' . $t_DP;
			}

			if ( $c_DP <= 10 ){
				push @filter_reasons, 'control_depth<10=' . $c_DP;
			}
			
			# Subtract control reads from tumour reads
			# If this number of SU is less than 10% of tumour read_depth then filter
			# if ( ( $tumour_read_support - $sc_direct_control_read_support ) / ( $t_DP + 0.01 ) < 0.1 ){ # Maybe this is too harsh...
			
			if ( $tumour_read_support / ( $t_DP + 0.01 ) < 0.1 ){
				# Unless there are both PE and SR supporting variant
				unless ($t_PE > 0 and $t_SR > 0){
					push @filter_reasons, 'tumour_reads/tumour_depth<10%=' . $tumour_read_support . "/" . $t_DP;
				}
			}
			
		}
		
		##################
		# Quality filter #
		##################
		
		if ( exists $sample_info{$id}{$tumour}{'SQ'} ){
			$sample_info{$id}{$tumour}{'SQ'} = 0 if $sample_info{$id}{$tumour}{'SQ'} eq '.';

			if ( $sample_info{$id}{$tumour}{'SQ'} <= 10 ){
				push @filter_reasons, "SQ=" . $sample_info{$id}{$tumour}{'SQ'};
			}
		}
						
		my ($chr2, $stop) = 0,0;

		if ($SV_type eq 'BND'){
			$chr2 = $alt =~ s/[\[\]N]//g;
			($chr2, $stop) = $alt =~ /(.+)\:(\d+)/;
			$SV_length = $stop - $start;
		}
		else {
		    ($stop) = $info_block =~ /;END=(.*?);/;
			
		}
		
	return ($SV_length, $chr2, $stop, $t_SR, $t_PE, \@filter_reasons);
}

sub delly {
	my ($info_block, $start, $SV_type, $filters) = @_;
	
	my @filter_reasons = @{ $filters };
	
    my ($stop) = $info_block =~ /;END=(.*?);/;
		
	my ($SV_length) = ($stop - $start);
	
		my ($t_SR, $t_PE) = (0,0);
		
		if ($info_block =~ /;SR=(\d+);/){
	   		$t_SR = $1;
	   	}
	   
	   if ($info_block =~ /;PE=(\d+);/){
	   		$t_PE = $1;
	   }
 	  		
		if ($start > $stop){
			my $old_start = $start;
			my $old_stop = $stop;
			$start = $old_stop;
			$stop = $old_start;
		}
		
		my ($chr2) = 0;
				
		if ($SV_type eq 'TRA'){
			($chr2) = $info_block =~ /CHR2=(.*?);/;
		}
		
	return ($SV_length, $chr2, $stop, $t_SR, $t_PE, \@filter_reasons );
}

sub summarise_variants {
	my ( $SVs, $filter_flag, $chromosome ) = @_;

	my ($dels, $dups, $trans, $invs, $filtered) = (0,0,0,0,0);

	my ( $query_region, $query_start, $query_stop );

	my $specified_region = 0;

	if ( $chromosome ){
		
		if ( $chromosome =~ /:/ ){
		
			($chromosome, $query_region) = split(/:/, $chromosome);
				
			if ( $query_region !~ /-/ ){
				die "Error parsing the specified region.\nPlease specify chromosome regions using the folloing format:\tchrom:start-stop\n";
			}
		
			($query_start, $query_stop) = split(/-/, $query_region);
			$query_start =~ s/,//g;
			$query_stop =~ s/,//g;
				
			say "Limiting search to SVs within region '$chromosome:$query_start-$query_stop'";
		
			$specified_region = 1;
		}
		else {
			say "Limiting search to SVs on chromosome '$chromosome'";
		}
		
	}
	
	
	my %support_by_chrom;
	
	my $read_support;
	
	my %filtered_sv;	
	
	for (keys %{ $SVs } ){
   	   
       my ( $chr, $start, $id, $ref, $alt, $quality_score, $filt, $info_block, $format_block, $tumour_info_block, $normal_info_block, $sv_type, $SV_length, $stop, $chr2, $SR, $PE, $filters ) = @{ $SVs->{$_} };
	   
	   if ( $chromosome ){		
	   		next if $chr ne $chromosome;
	   }
	
	   if ( $specified_region ){
		
	   		if ( ( $start < $query_start or $start > $query_stop ) and ( $stop < $query_stop or $stop > $query_stop ) ){
	   			next;
	   		}
	   	}
			
	   # Need this re-assignment for novobreak - should be harmless for lumpy and delly
	   $id = $_;
	   
	   my @filter_reasons = @{ $filters };
	   	   	   
		foreach (@filter_reasons){
			my ($reason) = $_ =~ /(.+)=/;
			$filtered_sv{$reason}++ ;
		}
	   	
		if ( scalar @filter_reasons > 0 ){
			$filtered++;
			next if $filter_flag;
		}
			
	   $read_support = ( $SR + $PE );
	   $support_by_chrom{$id} = [ $read_support, $sv_type, $chr, $SV_length ];
	  
	   $dels++ if $sv_type eq 'DEL';
	   $dups++ if $sv_type eq 'DUP';
	   $trans++ if $sv_type eq 'BND' or $sv_type eq 'TRA';
	   $invs++ if $sv_type eq 'INV';
	  
	}
	
	print "\n";
	if ($filter_flag){
		say "Running in filter mode: $filtered calls filtered out:";
		say " - $_: $filtered_sv{$_}" for sort {$filtered_sv{$b} <=> $filtered_sv{$a} } keys %filtered_sv;
		print "\n";		
	}

	say "$dels deletions";
	say "$dups duplications";
	say "$trans translocations";
	say "$invs inversions";
	
	my $top_count = 0;
	my %connected_bps;
	print "\nTop SVs by read count:\n";
	for ( sort { $support_by_chrom{$b}[0] <=> $support_by_chrom{$a}[0] } keys %support_by_chrom ){
		
		my $bp_id = $_;
		if ($bp_id =~ /_/){
			($bp_id) = $bp_id =~ /(.+)?_/;
		}
		
		# flatten connected bps into 1 id for summary	
		next if $connected_bps{$bp_id}++;
		$top_count++;
		
		print join("\n", "ID: $_", "TYPE: $support_by_chrom{$_}[1]", "CHROM: $support_by_chrom{$_}[2]", "READS: $support_by_chrom{$_}[0]", "LENGTH: $support_by_chrom{$_}[3]\n");
		print "\n";
		last if $top_count >= 5;
	}	
}

sub get_variant {
	
	my ($id_lookup, $SVs, $info, $filter_flag) = @_;
	
	if (not $info->{$id_lookup}){
		say "Couldn't find any variant with ID: '$id_lookup' in file. Abort";
		exit;
	}
	
	my (@format) 		= @{ $info->{$id_lookup}->[0]};
	my (%format_long) 	= @{ $info->{$id_lookup}->[1]}; #
	my (%info_long)		= @{ $info->{$id_lookup}->[2]};
	
	my (@tumour_parts) 	= @{ $info->{$id_lookup}->[3]};
	my (@normal_parts) 	= @{ $info->{$id_lookup}->[4]};
	
	my (%information)	= @{ $info->{$id_lookup}->[5]};
	my (%sample_info)	= @{ $info->{$id_lookup}->[6]};
					
	my ($chr, $start, $id, $ref, $alt, $quality_score, $filt, $info_block, $format_block, $tumour_info_block, $normal_info_block, $sv_type, $SV_length, $stop, $chr2, $SR, $PE, $filters, $samples ) = @{ $SVs->{$id_lookup} };
    
	my @filter_reasons = @{ $filters };
		
	my @samples = @{ $samples };
	
	if (scalar @filter_reasons > 0 ){
	say "\n______________________________________________";	
	say "Variant '$id_lookup' was filtered for the following reasons:";
	say "* $_" foreach @filter_reasons;
	say "______________________________________________\n";
	}
	
	printf "%-10s %-s\n",  			"ID:", 		$id_lookup;
	printf "%-10s %-s\n", 			"TYPE:", 	$sv_type;
	$chr2 ? printf "%-10s %-s\n",  	"CHROM1:", 	$chr : printf "%-10s %-s\n",  "CHROM:",  $chr;
	printf "%-10s %-s\n", 			"CHROM2:", 	$chr2 if $chr2;	
	printf "%-10s %-s\n",   		"START:", 	$start;
	printf "%-10s %-s\n",   		"STOP:",  	$stop;
	$chr2 ? printf "%-10s %-s\n",   "IGV:",   	"$chr:$start" : printf "%-10s %-s\n", "IGV:", "$chr:$start-$stop";
	printf "%-10s %-s\n", 			"LENGTH:", 	$SV_length;
	printf "%-10s %-s\n",   		"PE:",    	$PE;
	printf "%-10s %-s\n",   		"SR:",		$SR;
	printf "%-10s %-s\n",   		"QUAL:",   	$quality_score;
	printf "%-10s %-s\n",   		"FILT:",   	$filt;
	printf "%-10s %-s\n",   		"REF:",   	$ref;
	printf "%-10s %-s\n",   		"ALT:",   	$alt;
	
	say "__________________________________________________________________________________________________________________";
	printf "%-20s", 				"INFO";
	printf "%-20s", 				$_ for @samples;
	printf "%-s\n", 				"EXPLAINER";
	say "__________________________________________________________________________________________________________________";
	
	foreach my $format_block (@format){
		printf "%-20s", "$format_block";
		foreach (@samples){
			printf "%-20s", "$sample_info{$id_lookup}{$_}{$format_block}";
		}
		printf "%-s", "$format_long{$format_block}";
		print "\n";
	}

	say "____________________________________________________________________________________";
	printf "%-20s %-20s %-s\n", "INFO", "VALUE", "EXPLAINER";
	say "____________________________________________________________________________________";

	for (sort keys %{$information{$id_lookup}}){
		printf "%-20s %-20s %-s\n", $_, $information{$id_lookup}{$_}, $info_long{$_};
	}
	say "____________________________________________________________________________________";
		
}

sub dump_variants {
	
	my ( $SVs, $info, $filter_flag, $chromosome ) = @_;
	
	my ( $query_region, $query_start, $query_stop );
	
	my $specified_region = 0;
		
	if ( $chromosome ){
		
		if ( $chromosome =~ /:/ ){
		
			($chromosome, $query_region) = split(/:/, $chromosome);
				
			if ( $query_region !~ /-/ ){
				die "Error parsing the specified region.\nPlease specify chromosome regions using the folloing format:\tchrom:start-stop\n";
			}
		
			($query_start, $query_stop) = split(/-/, $query_region);
			$query_start =~ s/,//g;
			$query_stop =~ s/,//g;
				
			say "Limiting search to SVs within region '$chromosome:$query_start-$query_stop'";
		
			$specified_region = 1;
		}
		else {
			say "Limiting search to SVs on chromosome '$chromosome'";
		}
		
	}
				
	say "Enter any key to start cycling through calls or enter 'q' to exit";
	say "Running in filter mode - not displaying filtered calls" if $filter_flag;
	
	for (sort { @{ $SVs->{$a}}[0] cmp @{ $SVs->{$b}}[0] or
				@{ $SVs->{$a}}[1] <=> @{ $SVs->{$b}}[1] 
			}  keys %{ $SVs } ){
		
		my ( $chr, $start, $id, $ref, $alt, $quality_score, $filt, $info_block, $format_block, $tumour_info_block, $normal_info_block, $sv_type, $SV_length, $stop, $chr2, $SR, $PE, $filters, $samples ) = @{ $SVs->{$_} };
		
		$id = $_;
		
		if ( $chromosome ){		
			next if $chr ne $chromosome;
		}
		
		if ( $specified_region ){
			
			if ( ( $start < $query_start or $start > $query_stop ) and ( $stop < $query_stop or $stop > $query_stop ) ){
				next;
			}
			
		}
							
		my (@format) 		= @{ $info->{$_}->[0] };
		my (%format_long) 	= @{ $info->{$_}->[1] };
		my (%info_long)		= @{ $info->{$_}->[2] };
	
		my (@tumour_parts) 	= @{ $info->{$_}->[3] };
		my (@normal_parts) 	= @{ $info->{$_}->[4] };
	
		my (%information)	= @{ $info->{$_}->[5] };
		my (%sample_info)	= @{ $info->{$_}->[6] };
	
		
		my @filter_reasons = @{ $filters };
				
		my @samples = @{ $samples };
		
		if ( scalar @filter_reasons > 0 ){
			next if $filter_flag;
		}
		
		my $next_line = <>;
		say "Displaying info for variant '$id'. Enter any key to go to the next variant or type 'q' to exit\n";
		
		if ( $next_line ){
			chomp($next_line);
			exit if $next_line eq 'q';
						
			if (scalar @filter_reasons > 0 ){
				say "______________________________________________";	
				say "Variant '$id' was filtered for the following reasons:";
				say "* $_" foreach @filter_reasons;
				say "______________________________________________\n";
			}
	
			printf "%-10s %-s\n",  			"ID:", 		$id;
			printf "%-10s %-s\n", 			"TYPE:", 	$sv_type;
			$chr2 ? printf "%-10s %-s\n",  	"CHROM1:", 	$chr : printf "%-10s %-s\n",  "CHROM:",  $chr;
			printf "%-10s %-s\n", 			"CHROM2:", 	$chr2 if $chr2;	
			printf "%-10s %-s\n",   		"START:", 	$start;
			printf "%-10s %-s\n",   		"STOP:",  	$stop;
			$chr2 ? printf "%-10s %-s\n",   "IGV:",   	"$chr:$start" : printf "%-10s %-s\n", "IGV:", "$chr:$start-$stop";
			printf "%-10s %-s\n", 			"LENGTH:", 	$SV_length;
			printf "%-10s %-s\n",   		"PE:",    	$PE;
			printf "%-10s %-s\n",   		"SR:",		$SR;
			printf "%-10s %-s\n",   		"QUAL:",   	$quality_score;
			printf "%-10s %-s\n",   		"FILT:",   	$filt;
			printf "%-10s %-s\n",   		"REF:",   	$ref;
			printf "%-10s %-s\n",   		"ALT:",   	$alt;
			
			say "__________________________________________________________________________________________________________________";
			printf "%-20s", 				"INFO";
			printf "%-20s", 				$_ for @samples;
			printf "%-s\n", 				"EXPLAINER";
			say "__________________________________________________________________________________________________________________";
	
			foreach my $format_block (@format){
				printf "%-20s", 			$format_block;
				foreach (@samples){
					printf "%-20s", 		$sample_info{$id}{$_}{$format_block};
				}
				printf "%-s", 				$format_long{$format_block};
				print "\n";
			}

			say "____________________________________________________________________________________";
			printf "%-20s %-20s %-s\n", "INFO", "VALUE", "EXPLAINER";
			say "____________________________________________________________________________________";

			for (sort keys %{$information{$id}}){
				printf "%-20s %-20s %-s\n", $_, $information{$id}{$_}, $info_long{$_};
			}
			say "____________________________________________________________________________________";
	
		}
	}
	
}

sub chrom_filter {
	my ( $chr, $chr2, $filters ) = @_;
	
	my @keys = qw / 2L 2R 3L 3R 4 X Y /;
	my %chrom_filt;

	$chrom_filt{$_} = 1 for (@keys);
	
	my @filter_reasons = @{ $filters };
		 
	if ($chr2 eq '0'){
		$chr2 = $chr;
	}
	
	if ( not $chrom_filt{$chr} ){
		push @filter_reasons, 'chrom1=' . $chr;
	}
		
	elsif ( not $chrom_filt{$chr2} ){
		push @filter_reasons, 'chrom2=' . $chr2;
	}
	
	return (\@filter_reasons);

}

1;