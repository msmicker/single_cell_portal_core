require "test_helper"

class CacheManagementTest < ActionDispatch::IntegrationTest

  def setup
    host! 'localhost'
  end

  def test_manage_cache_entries
    puts "Test method: #{self.method_name}"

    study = Study.first
    cluster = ClusterGroup.first
    cluster_file = study.cluster_ordinations_files.first
    expression_file = study.expression_matrix_file
    cell_annotation = cluster.cell_annotations.sample
    annotation = "#{cell_annotation[:name]}--#{cell_annotation[:type]}--cluster"
    genes = ExpressionScore.all.map(&:gene)
    gene = genes.sample
    genes_hash = Digest::SHA256.hexdigest genes.sort.join

    # get various actions subject to caching
    xhr :get, render_cluster_path(study_name: study.url_safe_name, cluster: cluster.name, annotation: annotation)
    xhr :get, render_gene_expression_plots_path(study_name: study.url_safe_name, cluster: cluster.name, annotation: annotation, gene: gene)
    xhr :get, render_gene_set_expression_plots_path(study_name: study.url_safe_name, cluster: cluster.name, annotation: annotation, search: {genes: genes.join(' ')} )
    xhr :get, expression_query_path(study_name: study.url_safe_name, cluster: cluster.name, annotation: annotation, search: {genes: genes.join(' ')} )
    xhr :get, annotation_query_path(study_name: study.url_safe_name, annotation: annotation, cluster: cluster.name)

    # construct various cache keys for direct lookup (cannot lookup via regex)
    cluster_cache_key = "views/localhost/single_cell/study/#{study.url_safe_name}/render_cluster_#{cluster.name.split.join('-')}_#{annotation}.js"
    expression_cache_key = "views/localhost/single_cell/study/#{study.url_safe_name}/render_gene_expression_plots/#{gene}_#{cluster.name.split.join('-')}_#{annotation}.js"
    set_expression_cache_key = "views/localhost/single_cell/study/#{study.url_safe_name}/render_gene_set_expression_plots_#{cluster.name.split.join('-')}_#{annotation}_#{genes_hash}.js"
    exp_query_cache_key = "views/localhost/single_cell/study/#{study.url_safe_name}/expression_query_#{cluster.name.split.join('-')}_#{annotation}__#{genes_hash}.js"
    annot_query_cache_key = "views/localhost/single_cell/study/#{study.url_safe_name}/annotation_query_#{cluster.name.split.join('-')}_#{annotation}.js"

    assert Rails.cache.exist?(cluster_cache_key), "Did not find matching cluster cache entry at #{cluster_cache_key}"
    assert Rails.cache.exist?(expression_cache_key), "Did not find matching gene expression cache entry at #{expression_cache_key}"
    assert Rails.cache.exist?(set_expression_cache_key), "Did not find matching gene set expression cache entry at #{set_expression_cache_key}"
    assert Rails.cache.exist?(exp_query_cache_key), "Did not find matching expression query cache entry at #{exp_query_cache_key}"
    assert Rails.cache.exist?(annot_query_cache_key), "Did not find matching annotation query cache entry at #{annot_query_cache_key}"

    # load removal keys via associated study files
    cluster_file_cache_key = cluster_file.cache_removal_key
    expression_file_cache_key = expression_file.cache_removal_key

    # clear caches individually and assert removals
    CacheRemovalJob.new(cluster_file_cache_key).perform
    assert_not Rails.cache.exist?(cluster_cache_key), "Did not delete matching cluster cache entry at #{cluster_cache_key}"
    CacheRemovalJob.new(expression_file_cache_key).perform
    assert_not Rails.cache.exist?(expression_cache_key), "Did not delete matching gene expression cache entry at #{expression_cache_key}"
    assert_not Rails.cache.exist?(set_expression_cache_key), "Did not delete matching gene set expression cache entry at #{set_expression_cache_key}"
    assert_not Rails.cache.exist?(exp_query_cache_key), "Did not delete matching expression query cache entry at #{exp_query_cache_key}"
    CacheRemovalJob.new(study.url_safe_name).perform
    assert_not Rails.cache.exist?(annot_query_cache_key), "Did not delete matching annotation query cache entry at #{annot_query_cache_key}"

    puts "Test method: #{self.method_name} successful!"
  end

end