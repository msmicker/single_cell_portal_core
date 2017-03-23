module ApplicationHelper

	# set gene search placeholder value based on parameters
	def set_search_value
		if params[:search]
			if params[:search][:gene]
				@gene.gene
			elsif !params[:search][:genes].nil?
				@genes.map(&:gene).join(' ')
			end
		elsif params[:gene]
			params[:gene]
		else
			nil
		end
	end

	# create javascript-safe url with parameters
	def javascript_safe_url(url)
		URI.decode(url).html_safe
	end

	# construct nav menu breadcrumbs
	def set_breadcrumbs
		breadcrumbs = []
		if controller_name == 'site'
			if @study
				breadcrumbs << {title: "Study Overview", link: view_study_path(study_name: @study.url_safe_name)}
			end
			case action_name
				when 'view_gene_expression'
					breadcrumbs << {title: "Gene Expression <span class='badge'>#{params[:gene]}</span>", link: 'javascript:;'}
				when 'view_gene_set_expression'
					breadcrumbs << {title: "Gene Set Expression <span class='badge'>Multiple</span>", link: 'javascript:;'}
				when 'view_gene_expression_heatmap'
					breadcrumbs << {title: "Gene Expression <span class='badge'>Multiple</span>", link: 'javascript:;'}
				when 'view_precomputed_gene_expression_heatmap'
					breadcrumbs << {title: "Gene Expression <span class='badge'>#{params[:precomputed]}</span>", link: 'javascript:;'}
				when 'view_all_gene_expression_heatmap'
					breadcrumbs << {title: "Gene Expression <span class='badge'>All</span>", link: 'javascript:;'}
			end
		elsif controller_name == 'studies'
			breadcrumbs << {title: "My Studies", link: studies_path}
			case action_name
				when 'new'
					breadcrumbs << {title: "New Study", link: 'javascript:;'}
				when 'edit'
					breadcrumbs << {title: "Editing '#{truncate(@study.name, length: 20)}'", link: 'javascript:;'}
				when 'show'
					breadcrumbs << {title: "Showing '#{truncate(@study.name, length: 20)}'", link: 'javascript:;'}
				when 'initialize_study'
					breadcrumbs << {title: "Upload/Edit Study Data", link: 'javascript:;'}
				when 'sync_study'
					breadcrumbs << {title: "Syncronize Workspace", link: 'javascript:;'}
			end
		end
		breadcrumbs
	end

	# construct a dropdown for navigating to single gene-level expression views
	def load_gene_nav(genes)
		nav = [['All queried genes', '']]
		genes.map(&:gene).each do |gene|
			nav << [gene, view_gene_expression_url(study_name: params[:study_name], gene: gene)]
		end
		nav
	end

	# method to set cluster value based on options and parameters
	# will default to first cluster if none are specified
	def set_cluster_value(clusters, parameters)
		if !parameters[:gene_set_cluster].nil?
			parameters[:gene_set_cluster]
		elsif !parameters[:cluster].nil?
			parameters[:cluster]
		else
			clusters.first
		end
	end

	# method to set annotation value by parameters or load a 'default' annotation when first loading a study (none have been selected yet)
	# will load the first cluster-based annotation if available, otherwise will default to first study-based instead
	def set_annotation_value(annotations, parameters)
		if !parameters[:gene_set_annotation].nil?
			parameters[:gene_set_annotation]
		elsif !parameters[:annotation].nil?
			parameters[:annotation]
		else
			annotations['Cluster-based'].empty? ? annotations['Study Wide'].first.last : annotations['Cluster-based'].first.last
		end
	end

end
