#!/usr/bin/env ruby

# Copyright (c) 2010 Geza Kovacs
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'optparse'
require 'tmpdir'
require 'fileutils'

def shell_escape(str)
  "'" + str.gsub("'", "'\\''") + "'"
end

def sh(cmd, *args)
  outl = []

  unless args.empty?
    cmd = shell_escape(cmd) + ' '
    cmd << args.map { |w| shell_escape(w) }.join(' ')
  end

  IO.popen(cmd) do |f|
    until f.eof?
      tval = f.gets
      puts tval
      outl.push(tval)
    end
  end

  outl.join('')
end

def writef(filename, text)
  File.open(filename, 'w') do |f|
    f.puts(text)
  end
end

class Configuration

  attr_accessor :opts
  attr_accessor :show_version, :show_help
  attr_accessor :infile, :outfile, :run_unpaper
  attr_accessor :use_tesseract, :use_cuneiform, :use_ocropus
  attr_accessor :language, :check_lang
  attr_accessor :delete_dir, :delete_files, :tmp
  attr_accessor :use_ppm, :use_png

  def initialize
    @infile = nil
    @outfile = nil
    @delete_dir = true
    @delete_files = true
    @language = 'eng'
    @check_lang = false
    @tmp = nil
    @use_ocropus = false
    @use_cuneiform = false
    @use_tesseract = false
    @run_unpaper = false

    @use_ppm = true
    @use_png = false

    @show_version = false
    @show_help = false
  end

end

class OptionParser

  def self.options
    @@options
  end

  def self.configuration
    @@configuration
  end

  def self.prepare(app_name)
    @@configuration = Configuration.new

    @@options = OptionParser.new do |opts|

      opts.banner = <<~USAGE
        Usage: #{app_name} -i input.pdf -o output.pdf
        #{app_name} adds text to PDF files using the ocropus, cuneiform, or tesseract OCR software
      USAGE
    
      opts.on('-i', '--input [FILE]', 'Specify input PDF file') do |fn|
        @@configuration.infile = fn
      end
    
      opts.on('-o', '--output [FILE]', 'Specify output PDF file') do |fn|
        @@configuration.outfile = fn
      end
    
      opts.on('-u', '--unpaper', 'Run unpaper on each page before OCR.') do
        @@configuration.run_unpaper = true
      end
    
      opts.on('-t', '--tesseract', 'Use tesseract as the OCR engine (default)') do
        @@configuration.use_tesseract = true
      end
    
      opts.on('-c', '--cuneiform', 'Use cuneiform as the OCR engine') do
        @@configuration.use_cuneiform = true
      end
    
      opts.on('-p', '--ocropus', 'Use ocropus as the OCR engine') do
        @@configuration.use_ocropus = true
      end
    
      opts.on('-l', '--lang [LANG]', 'Specify language for the OCR software') do |fn|
        @@configuration.language = fn
        @@configuration.check_lang = true
      end
    
      opts.on('-L', '--nocheck-lang LANG', 'Suppress checking of language parameter') do |fn|
        @@configuration.language = fn
        @@configuration.check_lang = false
      end
    
      opts.on('-w', '--workingdir [DIR]', 'Specify directory to store temp files in') do |fn|
        @@configuration.delete_dir = false
        @@configuration.tmp = fn
      end
    
      opts.on('-k', '--keep', 'Keep temporary files around') do
        @@configuration.delete_files = false
      end
    
      opts.on_tail('-h', '--help', 'Show this message') do
        @@configuration.show_help = true
      end
    
      opts.on_tail('-v', '--version', 'Show version') do
        @@configuration.show_version = true   
      end
    end    

    return self

  end

  def self.parse(arguments)
    @@options.parse!(arguments)
    return @@configuration
  end
end


def valide_infile?(infile)

  if !infile || infile == ''
    puts OptionParser.options
    puts
    puts 'Need to specify an input PDF file'
    return false
  end
  
  if infile[-3..-1].casecmp('pdf') != 0
    puts "Input PDF file #{infile} should have a PDF extension"
    return false
  end
  
  unless File.file?(infile)
    puts "Input file #{infile} does not exist"
    return false
  end

  return true

end

def valid_outfile?(outfile)

  # We don't need to validate outfile != infile because 
  # we validate here that outfile does not exists
  # and we are validating that infile exists

  if !outfile || outfile == ''
    puts OptionParser.options
    puts
    puts 'Need to specify an output PDF file'
    exit
  end
  
  if outfile[-3..-1].casecmp('pdf') != 0
    puts 'Output PDF file should have a PDF extension'
    exit
  end

  if File.file?(outfile)
    puts "Output file #{outfile} already exists"
    exit
  end

end

def valid_parameters?(params)

  return false unless valid_infile?(params.infile)
  return false unless valid_outfile?(params.outfile)

  if !params.language || params.language == ''
    puts 'Need to specify a language'
    return false
  end
  
  if `which pdftk` == ''
    puts 'pdftk command is missing. Install the pdftk package'
    return false
  end
  
  if `which pdftoppm` == ''
    puts 'pdftoppm command is missing. Install the poppler-utils package'
    return false
  end

  if `which hocr2pdf` == ''
    puts 'hocr2pdf command is missing. Install the exactimage package'
    return false
  end
  
  if params.use_ocropus
    if `which ocroscript` == ''
      puts 'The ocroscript command is missing. Install the ocropus package.'
      return false
    end
  elsif params.use_cuneiform
    if `which cuneiform` == ''
      puts 'The cuneiform command is missing. Install the cuneiform package.'
      return false
    end
  elsif params.use_tesseract
    if `which tesseract` == ''
      puts 'The tesseract command is missing. Install the tesseract-ocr package and the'
      puts 'language packages you need, e.g. tesseract-ocr-deu, tesseract-ocr-deu-frak,'
      puts 'or tesseract-ocr-eng.'
      return false
    end
  else
    # This is not a validation, it should be removed from here
    if `which tesseract` != ''
      params.use_tesseract = true
    elsif `which cuneiform` != ''
      params.use_cuneiform = true
    elsif `which ocroscript` != ''
      params.use_ocropus = true
    else
      puts 'The tesseract command is missing. Install the tesseract-ocr package and the'
      puts 'language packages you need, e.g. tesseract-ocr-deu, tesseract-ocr-deu-frak,'
      puts 'or tesseract-ocr-eng.'
      exit
    end
  end

  if params.run_unpaper
    if `which unpaper` == ''
      puts 'The unpaper command is missing. Install the unpaper package.'
      return false
    end
  end

  if params.check_lang
    langlist = []
    if params.use_cuneiform
      begin
        langlist = `cuneiform -l`.split("\n")[-1].split(':')[-1].delete('.').split(' ')
      rescue
        puts 'Unable to list supported languages from cuneiform'
      end
    end
    if params.use_tesseract
      begin
        langlist = `tesseract --list-langs 2>&1`.split("\n")[1..-1]
      rescue
        puts 'Unable to list supported languages from tesseract'
      end
    end
    if langlist && !langlist.empty?
      unless langlist.include?(params.language)
        puts "Language #{params.language} is not supported or not installed. Please choose from"
        puts langlist.join(' ')
        return false
      end
    end
  end

  return true

end


app_name = 'pdfocr'
version = [0, 1, 4]

params = OptionParser.prepare(app_name).parse(ARGV)
exit unless valid_parameters?(params)

tmp = params.tmp

if params.show_help
  puts OptionParser.options
  exit
end

if params.show_version
  puts version.join('.')
  exit    
end

infile = File.expand_path(params.infile)
outfile = File.expand_path(params.outfile)

if params.delete_dir
  tmp = Dir.mktmpdir
elsif File.directory?(tmp)
  tmp = "#{File.expand_path(tmp)}/pdfocr"
  if File.directory?(tmp)
    puts "Directory #{tmp} already exists - remove it"
    exit
  else
    Dir.mkdir(tmp)
  end
else
  puts "Working directory #{tmp} does not exist"
  exit
end



puts "Input file is #{infile}"
puts "Output file is #{outfile}"
puts "Using working dir #{tmp}"

puts 'Getting info from PDF file'
puts

pdfinfo = sh 'pdftk', infile, 'dump_data'

if !pdfinfo || pdfinfo == ''
  puts "Error: didn't get info from pdftk #{infile} dump_data"
  exit
end

puts

begin
  pdfinfo =~ /NumberOfPages: (\d+)/
  pagenum = Regexp.last_match(1).to_i
rescue
  puts "Error: didn't get page count for #{infile} from pdftk"
  exit
end

if pagenum.zero?
  puts "Error: there are 0 pages in the input PDF file #{infile}"
  exit
end

writef("#{tmp}/pdfinfo.txt", pdfinfo)

puts "Converting #{pagenum} pages"

numdigits = pagenum.to_s.length

Dir.chdir("#{tmp}/") do
  1.upto(pagenum) do |i|
    puts '=========='
    puts "Extracting page #{i}"
    basefn = i.to_s.rjust(numdigits, '0')
    sh 'pdftk', infile, 'cat', i.to_s, 'output', "#{basefn}.pdf"
    unless File.file?("#{basefn}.pdf")
      puts "Error while extracting page #{i}"
      next
    end
    
    if params.use_ppm
      puts "Converting page #{i} to ppm"
      image_extension = "ppm"

      sh "pdftoppm -r 300 #{shell_escape(basefn)}.pdf >#{shell_escape(basefn)}.ppm"
      unless File.file?("#{basefn}.ppm")
        puts "Error while converting page #{i} to ppm"
        next
      end      
    end

    if params.use_png
      puts "Converting page #{i} to png"
      image_extension = "png"

      sh "convert -density 360 #{shell_escape(basefn)}.pdf -quality 35 #{shell_escape(basefn)}.png"
      if not File.file?(basefn+'.png')
        puts "Error while converting page #{i} to png"
        next
      end
    end
    
    if params.run_unpaper
      puts "Running unpaper on page #{i}"
      sh 'unpaper', "#{basefn}." + image_extension, "#{basefn}_unpaper." + image_extension
      unless File.file?("#{basefn}_unpaper." + image_extension)
        puts "Error while running unpaper on page #{i}"
        next
      end
      sh 'mv', "#{basefn}_unpaper." + image_extension, "#{basefn}." + image_extension
    end

    puts "Running OCR on page #{i}"
    if params.use_cuneiform
      sh 'cuneiform', '-l', params.language, '-f', 'hocr', '-o', "#{basefn}.hocr", "#{basefn}." + image_extension
    elsif params.use_tesseract
      sh 'tesseract', '-l', params.language, "#{basefn}." + image_extension, "#{basefn}-new", 'pdf'
      unless File.file?("#{basefn}-new.pdf")
        puts "Error while running OCR on page #{i}"
        sh 'mv', "#{basefn}.pdf", "#{basefn}-new.pdf"
      end
      puts 'Merging ...'
      sh "pdftk #{tmp + '/' + '*-new.pdf'} cat output #{tmp + '/merged.ocrpdf'}"
      sh "rm -f #{tmp + '/' + '*-new.pdf'}"
      sh "rm -f #{tmp + '/' + '*.ppm'}"
      sh "rm -f #{tmp + '/' + '*.png'}"
      sh "rm -f #{tmp + '/' + '*.pdf'}"
      sh "mv #{tmp + '/merged.ocrpdf'} #{tmp + '/0000000000000-merged-new.pdf'}"
    else
      sh "ocroscript recognize #{shell_escape(basefn)}."+image_extension + " > #{shell_escape(basefn)}.hocr"
    end

    next if params.use_tesseract

    unless File.file?("#{basefn}-new.pdf")
      puts "Error while running OCR on page #{i}"
      next
    end
  end
end

if params.use_tesseract
  puts 'renaming merged-new.pdf to merged.pdf'
  sh 'mv', "#{tmp}/0000000000000-merged-new.pdf", "#{tmp}/merged.pdf"
else
  puts 'Merging together PDF files'
  sh 'pdftk', "#{tmp}/*-new.pdf", 'cat', 'output', "#{tmp}/merged.pdf"
end

puts "Updating PDF info for #{outfile}"

sh 'pdftk', "#{tmp}/merged.pdf", 'update_info', "#{tmp}/pdfinfo.txt", 'output', outfile

if params.delete_files
  puts 'Cleaning up temporary files'
  FileUtils.rm_rf(tmp)
end
