require 'csv'
require 'faraday'
require 'json'
require 'logger'
require 'dotenv'
Dotenv.load

# Настройка логгера
LOGGER = Logger.new('invite_users.log', 'daily')
LOGGER.level = Logger::INFO

API_URL = ENV['PACHCA_API_URL'] || 'https://api.pachca.com/api/shared/v1'
TOKEN = ENV['PACHCA_ADMIN_TOKEN']

unless TOKEN
  puts 'Ошибка: переменная окружения PACHCA_ADMIN_TOKEN не задана.'
  LOGGER.fatal('Не задан токен администратора (PACHCA_ADMIN_TOKEN)')
  exit(1)
end

# Чтение пользователей из CSV
users = []
begin
  CSV.foreach('users.csv', headers: true) do |row|
    users << row.to_h
  end
rescue => e
  puts "Ошибка чтения users.csv: #{e.message}"
  LOGGER.fatal("Ошибка чтения users.csv: #{e.message}")
  exit(1)
end

# Валидация и отправка приглашений
users.each_with_index do |user, i|
  # Валидация обязательных полей
  if user['email'].to_s.strip.empty? || user['role'].to_s.strip.empty? || user['first_name'].to_s.strip.empty? || user['last_name'].to_s.strip.empty?
    msg = "Строка #{i+2}: Пропущены обязательные поля (email, role, first_name, last_name)"
    puts msg
    LOGGER.error(msg)
    next
  end

  user_data = {
    email: user['email'],
    role: user['role'],
    first_name: user['first_name'],
    last_name: user['last_name'],
    nickname: user['nickname'],
    department: user['department'],
    phone_number: user['phone_number'],
    title: user['title']
  }

  # Добавляем теги, если есть
  if user['tags'] && !user['tags'].strip.empty?
    tags = user['tags'].split(/[,;]/).map(&:strip).reject(&:empty?)
    user_data[:list_tags] = tags unless tags.empty?
  end

  payload = { user: user_data.compact }

  begin
    response = Faraday.post(
      "#{API_URL}/users",
      JSON.generate(payload),
      {
        'Authorization' => "Bearer #{TOKEN}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    )
    if [200, 201].include?(response.status)
      puts "Пользователь #{user['email']} успешно приглашён."
      LOGGER.info("Пользователь #{user['email']} успешно приглашён.")
    else
      if response.status == 409 && response.body.include?("already_exists")
        msg = "Пользователь #{user['email']} уже существует в системе, приглашение не требуется."
        puts msg
        LOGGER.info(msg)
      else
        error_msg = "Ошибка для #{user['email']}: #{response.status} #{response.body}"
        puts error_msg
        LOGGER.error(error_msg)
      end
    end
  rescue Faraday::Error => e
    puts "Ошибка сети для #{user['email']}: #{e.message}"
    LOGGER.error("Ошибка сети для #{user['email']}: #{e.message}")
  rescue => e
    puts "Неизвестная ошибка для #{user['email']}: #{e.message}"
    LOGGER.error("Неизвестная ошибка для #{user['email']}: #{e.message}")
  end
end
