puts "Loading Logger"
module MpdLogger
  def self.debug(message)
    return
    puts "DEBUG: #{message}"
  end

  def self.info(message)
    puts "INFO:  #{message}"
  end
end
