def rm(path)
  Dir.glob(Rails.root + path).each do |file|
    puts file if ENV["VERBOSE"]
    `rm -f #{file}`
  end
end

namespace :assets do
  desc "Clear cached assets"
  task :clear do
    rm("public/stylesheets/gts-*.css")
    rm("public/stylesheets/all.css")
    rm("public/javascripts/gts-*.js")
    rm("public/javascripts/all.js")
    rm("public/javascripts/capillary.js")
    rm("public/**/*/gts-*.*")
    puts "Removed generated stylesheets and javascripts"
  end
end
