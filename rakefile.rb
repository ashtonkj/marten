require 'json'

COMPILE_TARGET = ENV['config'].nil? ? "debug" : ENV['config']
RESULTS_DIR = "results"
BUILD_VERSION = '1.2.4';
CONNECTION = ENV['connection']

tc_build_number = ENV["BUILD_NUMBER"]
build_revision = tc_build_number || Time.new.strftime('5%H%M')
build_number = "1.2.4.#{build_revision}"
BUILD_NUMBER = build_number

task :ci => [:connection, :version, :default, 'nuget:pack']

# TODO: put :storyteller back -- task :default => [:mocha, :test, :storyteller]
task :default => [:mocha, :test]

desc "Prepares the working directory for a new build"
task :clean do
  #TODO: do any other tasks required to clean/prepare the working directory
  FileUtils.rm_rf RESULTS_DIR
  FileUtils.rm_rf 'artifacts'

end

desc "Update the version information for the build"
task :version do
  asm_version = build_number

  begin
    commit = `git log -1 --pretty=format:%H`
  rescue
    commit = "git unavailable"
  end
  puts "##teamcity[buildNumber '#{build_number}']" unless tc_build_number.nil?
  puts "Version: #{build_number}" if tc_build_number.nil?

  options = {
      :description => 'Postgresql as a Document Db and Event Store for .Net Development',
      :product_name => 'Marten',
      :copyright => 'Copyright 2016 Jeremy D. Miller et al. All rights reserved.',
      :trademark => commit,
      :version => asm_version,
      :file_version => build_number,
      :informational_version => asm_version

  }

  puts "Writing src/CommonAssemblyInfo.cs..."
  File.open('src/CommonAssemblyInfo.cs', 'w') do |file|
    file.write "using System.Reflection;\n"
    file.write "using System.Runtime.InteropServices;\n"
    file.write "[assembly: AssemblyDescription(\"#{options[:description]}\")]\n"
    file.write "[assembly: AssemblyProduct(\"#{options[:product_name]}\")]\n"
    file.write "[assembly: AssemblyCopyright(\"#{options[:copyright]}\")]\n"
    file.write "[assembly: AssemblyTrademark(\"#{options[:trademark]}\")]\n"
    file.write "[assembly: AssemblyVersion(\"#{build_number}\")]\n"
    file.write "[assembly: AssemblyFileVersion(\"#{options[:file_version]}\")]\n"
    file.write "[assembly: AssemblyInformationalVersion(\"#{options[:informational_version]}\")]\n"
  end

  puts 'Writing version to project.json'
  nuget_version = "#{BUILD_VERSION}"
  project_file = load_project_file('src/Marten/project.json')
  File.open('src/Marten/project.json', "w+") do |file|
    project_file["version"] = nuget_version
    file.write(JSON.pretty_generate project_file)
  end
end

desc 'Builds the connection string file'
task :connection do
  File.open('src/Marten.Testing/connection.txt', 'w') do |file|
    file.write CONNECTION
  end
end

desc 'Runs the Mocha tests'
task :mocha do
  sh "npm install"
  sh "npm run test"
end

desc 'Compile the code'
task :compile => [:clean, :restore] do
  sh "dotnet build ./src/Marten.Testing/ --configuration #{COMPILE_TARGET}"
end

desc 'Run the unit tests'
task :test => [:compile] do
  sh 'dotnet test src/Marten.Testing --framework netcoreapp1.0'
end


desc "Launches VS to the Marten solution file"
task :sln do
  sh "start src/Marten.sln"
end

desc "Run the storyteller specifications"
task :storyteller => [:compile] do
  storyteller_cmd = storyteller_path()
  sh "#{storyteller_cmd} run src/Marten.Testing --results-path artifacts/stresults.htm --build #{COMPILE_TARGET}/net46/win7-x64"
end

desc "Run the storyteller specifications"
task :open_st => [:compile] do
  storyteller_cmd = storyteller_path()
  sh "#{storyteller_cmd} open src/Marten.Testing"
end

desc "Launches the documentation project in editable mode"
task :docs => [:restore] do
  storyteller_cmd = storyteller_path()
  sh "#{storyteller_cmd} doc-run -v #{BUILD_VERSION}"
end

desc 'Restores nuget packages'
task :restore do
    sh 'dotnet restore src/Marten'
    sh 'dotnet restore src/Marten.CommandLine'
    sh 'dotnet restore src/Marten.Testing.OtherAssembly'
    sh 'dotnet restore src/Marten.Testing'
end


desc 'Build the Nupkg file'
task :pack => [:compile] do
	sh "dotnet pack ./src/Marten -o artifacts"
	sh "dotnet pack ./src/Marten.CommandLine -o artifacts"
end

def storyteller_path()
  global_cache = `./nuget.exe locals global-packages -list`
  global_cache = global_cache.split(': ').last.strip
  project_file = load_project_file("src/Marten.Testing/project.json")
  storyteller_version = project_file["frameworks"]["net46"]["dependencies"]["Storyteller"]
  "#{global_cache}Storyteller/#{storyteller_version}/tools/st.exe"
end

def load_project_file(project)
  File.open(project) do |file|
    file_contents = File.read(file, :encoding => 'bom|utf-8')
    JSON.parse(file_contents)
  end
end
