require 'pg'
require 'highline/import'

module PasswordManagement
  COLUMNS = {
    'n' => 'name',
    'u' => 'username',
    'p' => 'password',
    'm' => 'pwdmnemonic',
    'e' => 'email',
    'o' => 'other',
  }
  OPTION = {
    '-f' => ->node, &blk { puts blk.call(node).encode @@encoding; puts },
    'default' => ->node { puts "    #{node['name']}".encode @@encoding },
  }
  USAGE = <<-EOF
Usage: ruby PasswordManagement.rb [commands] name [options]
    use 'ruby PasswordManagement.rb -h' to see help
  EOF
  INFINITY = 1.0 / 0
  # TODO: encoding seems not useful, maybe remove it?
  @@encoding = 'big5'
  @@option = 'default'

  class << self
    private 
    def check_input(input, length_limit = 1)
      length_limit = Proc.new if block_given?

      unless length_limit === input.length
        error_message = 'Wrong number of arguments(%s)'
        limit_message = case length_limit
                        when Proc then input.size.to_s
                        when Range then "#{input.size} in #{length_limit}"
                        else "#{input.size} for #{length_limit}"
                        end
        puts error_message % limit_message
        display_usage_message_and_quit
      end
    end
    #default length constraint is 1
    def check_and_execute(method_name, input, length_limit = 1, &blk)
      check_input(input, length_limit, &blk)
      escape_newline! input
      send(method_name, *input)
    end

    def warning(warn)
      puts warn
      exit
    end

    def escape_newline!(input)
      input.map! { |e| e.gsub(/\\n/,"\n") }
    end

    def determine_append_option(input)
      append_option = {Y: true, y: true, N: false, n: false}
      if append_option.include? input[2].to_sym
        input[2] = append_option[input[2].to_sym]
      else 
        input.insert(2, false)
      end
    end

    def blank_name_update_check(column, append_data, *new_data)
      if column == 'n' and !append_data and (new_data[0].nil? or new_data[0].empty?)
        warning 'Cannot change name to blank!'
      end
    end

    def ask_column(name, column)
      print "Original #{COLUMNS[column]} in #{name}: "
      p check_and_get_old_data(COLUMNS[column], name)[COLUMNS[column]].encode @@encoding
      print "New #{COLUMNS[column]} in #{name}: "
      STDIN.gets.chomp
    end

    def display_usage_message_and_quit
      warning USAGE
    end

    def open_database
      begin
      @@db = PG::Connection.open(:dbname => 'Accounts', :user => 'mars26', :password => @@password)
      rescue PG::Error => e
        warning 'Password incorrect!'
      end
    end

    def close_database
      @@db.close
    end

    def display_result(accounts, *messages, &blk)
      warning 'No result found!' if accounts.to_a.empty?
      warning 'Option incorrect!' unless OPTION.include? @@option

      accounts.each_with_index do |node, index|
        puts yield(node, index).encode @@encoding
      end
    end

    def check_data_exist(column, name)
      @@db.exec_params("SELECT #{column} FROM account WHERE name = $1", [name])
    end

    def check_and_get_old_data(column, name)
      old_data = check_data_exist(column, name).first
      warning "Cannot found #{name}!" unless old_data
      old_data
    end

    def check_account(accounts, name)
      if (node = accounts.detect { |node| node['name'] == name })
        accounts.replace([node]) and return ''
      end
      accounts.size == 1 ? 'Found one account with similar name:' : ''
    end

    #command: 'i', insert data to account. All inputs behind 'email' column will be concatenated by join(" ") and put into 'other' column
    def insert_account(name, *other)
      puts "Adding #{name} to Table"
      unless check_data_exist('name', name).to_a.empty?
        warning "#{name} already in Table!"
      end

      user, pwd, pm, email, *other = other
      @@db.exec_params('INSERT INTO account (name, username, password, pwdmnemonic, email, other) VALUES ($1, $2, $3, $4, $5, $6)',
                       [name, user, pwd, pm, email, other.join(' ')])
    end

    def _find_account(name)
      accts = @@db.exec_params('SELECT * FROM account WHERE name LIKE $1 ORDER BY LOWER(name)', ["%#{name}%"]).to_a

      messages = [check_account(accts, name), 'Found several accounts:']

      [accts, messages]
    end

    #command: 'p', list password of specific account, normal usage. use '-f' option can force to list all data found
    def find_password(name)
      accts, messages = _find_account(name)

      puts (accts.size == 1) ? messages[0] : messages[1]
      display_result(accts) do |node, index|
        if accts.size == 1 || @@option == '-f'
          <<-EOF.gsub!(/^\s*/,'    ')
          Name: #{node['name']}
          Username: #{node['username']}
          Password: #{node['password']}

          EOF
        elsif @@option == 'default'
          "    #{node['name']}"
        end
      end
    end

    #command: 'a', list all the data of specific account. use '-f' option can force to list all data found
    def find_account(name)
      accts, messages = _find_account(name)

      puts (accts.size == 1) ? messages[0] : messages[1]
      display_result(accts) do |node, index|
        if accts.size == 1 || @@option == '-f'
          <<-EOF.gsub!(/^\s*/,'    ')
          Name: #{node['name']}
          Username: #{node['username']}
          Password: #{node['password']}
          Password Mnemonic: #{node['pwdmnemonic']}
          Email: #{node['email']}
          Other: #{node['other']}

          EOF
        elsif @@option == 'default'
          "    #{node['name']}"
        end
      end
    end

    #command: 'l', list all accounts' name. use '-f' option can force to list all data found(looks the same)
    def list_all_accounts
      accounts = @@db.exec('SELECT name FROM account ORDER BY LOWER(name)')

      puts 'list of accounts:'
      display_result(accounts) { |node, _| "    #{node['name']}" }
    end

    #command: 'd', delete specific account
    def delete_account name 
      puts "Deleting #{name} from Table"
      check_and_get_old_data 'name', name
      @@db.exec_params('DELETE FROM account WHERE name = $1', [name])
    end

    #command: 'E', eliminate all accounts, use Capital case to keep from "mistouch"
    def eliminate_all_accounts
      puts 'Are you SERIOUS? Please Enter yes'
      unless $stdin.gets.strip.downcase == 'yes'
        warning 'Exit without elimination'
      end

      puts 'Deleting all entries in Table'
      @@db.exec('DELETE FROM account')
    end

    #command: 'u', update specific column of data in specific account. If no new data, the column of data will be cleared
    def update_column_of_account(name, column, append_data = false, *new_data)
      puts "Updating #{COLUMNS[column]} in #{name}"
      old_data = check_and_get_old_data(COLUMNS[column], name)
      old_data = append_data ? old_data[COLUMNS[column]] : ''

      begin
        @@db.exec_params("UPDATE account SET #{COLUMNS[column]} = $1 WHERE name = $2", [old_data + new_data.join(' '), name])
      rescue PG::Error => e
        warning "#{new_data[0]} already in Table!"
      end
    end

    #command: 'L', list all columns in table, for update command
    def list_columns
      result = []
      result << 'list of columns to update:'
      result.push *COLUMNS.map { |k, v| "    #{k}    #{v}" }
      result << '         other can accept variables and concatenated by space'
      result
    end

    #command: 's', search word in the 'other' column
    def search_word(word)
      accts = @@db.exec_params('SELECT name, other FROM account WHERE other LIKE $1', ["%#{word}%"])

      puts 'Search result:'
      display_result(accts) do |node, _|
          <<-EOF.gsub!(/^\s*/,'    ')
          Name: #{node['name']}
          Other: #{node['other']}

          EOF
      end
    end

    public
    #all commands: 'a', 'd', 'E', 'i', 'l', 'L', 'p', 's', 'u', 'B', 'U'. Can accept multirequests separated by '\' or array of arrays
    def execute(*inputs)
      @@password = ask('Please Enter Password') { |q| q.echo = false }

      open_database
      at_exit { close_database }

      queries = case inputs[0]
                when Array then inputs
                when nil then [[]]
                else inputs.chunk { |e| e != '\\' || nil }.map &:last
                end

      queries.each do |input|
        command = input.shift
        case command
        when 'a'
          @@option = input.pop if input.size == 2
          check_and_execute :find_account, input
        when 'd'; check_and_execute :delete_account, input
        when 'E'; check_and_execute :eliminate_all_accounts, input, 0
        when 'i'; check_and_execute :insert_account, input, 1..INFINITY
        when 'I'
          check_input input

          COLUMNS.values[1..-1].each do |column|
            print "#{column}: "
            input << STDIN.gets.chomp
          end

          escape_newline! input
          insert_account *input
        when 'l'; check_and_execute :list_all_accounts, input, 0
        when 'L'
          check_input input, 0
          puts list_columns
        when 'p'
          @@option = input.pop if input.size == 2
          check_and_execute :find_password, input
        when 's'
          check_and_execute :search_word, input
        when 'u'
          check_input input, 2..INFINITY
          warning list_columns unless COLUMNS.include? input[1]
          check_input input, 2..4 unless input[1] == 'o'
          
          input[2] = ask_column(input[0], input[1]) if input.size == 2

          escape_newline! input
          determine_append_option input
          blank_name_update_check *input.drop(1)

          update_column_of_account *input
        when 'sudo'
          File.open('privilege', 'w') do |file|
            file.write(Base64.encode64(Marshal.dump(Time.now)))
          end
        when 'B' then @@encoding = 'big5'
        when 'U' then @@encoding = 'utf-8'
        when '-h'
          puts USAGE
          puts
          puts <<-EOF
commands list:
    a    find account. -f to force display all results
    d    delete account
    E    eliminate all accounts
    i    insert account(name, username, password, pwdmnemonic, email, other)
    I    insert account by using prompt
    l    list all accounts
    L    list account columns
    p    find password. -f to force display all results
    s    search word in 'other' column
    u    update column of account(name, column, append, data)
         append = Y/y/N/n
         Without append and data, a prompt will appear to ask
         data.

    B    Big5 encoding, default
    U    UTF-8 encoding
         use for redirect to file

    If you want to input multiple query, you can use '\\\\' to separate them.
          EOF
          puts
          puts list_columns
        else display_usage_message_and_quit
        end
        puts
      end
      exit
    end
  end
end

if __FILE__ == $0
  PasswordManagement.execute *ARGV
end
