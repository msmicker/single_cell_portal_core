module StudiesHelper
	def get_boolean_label(field)
		field ? "<span class='fa fa-check text-success'></span>".html_safe : "<span class='fa fa-times text-danger'></span>".html_safe
	end

	def get_na_label
		"<span class='label label-default'><i class='fa fa-ban' aria-hidden='true'></i> N/A</span>".html_safe
	end


	def required_help_text
		{
				'Cluster Assignments' => "<strong><span class='fa fa-exclamation-triangle'></span> Requirements:</strong> A tab-delimited .txt file with the following column headers: 'CELL_NAME', 'CLUSTER', and 'SUB-CLUSTER'",
				'Cluster Coordinates' => "<strong><span class='fa fa-exclamation-triangle'></span> Requirements:</strong> A tab-delimited .txt file with the following column headers: 'CELL_NAME', 'X', and 'Y'<br/><strong><span class='fa fa-exclamation-triangle'></span> Requirements:</strong> Must have also uploaded a cluster assignments file in order to parse",
				'Expression Matrix' => "<strong><span class='fa fa-exclamation-triangle'></span> Requirements:</strong> A tab-delimited .txt file with gene names in the first column, and single cell names in each successive column",
				'Marker Gene List' => "<strong><span class='fa fa-exclamation-triangle'></span> Requirements:</strong> A tab-delimited .txt file with gene names in the first column, and cluster names in each successive column",
				'Fastq' => "<strong><span class='fa fa-exclamation-triangle'></span> Requirements:</strong> Must be non-human data",
				'Documentation' => 'No requirements',
				'Other' => 'No requirements'
		}
	end
end