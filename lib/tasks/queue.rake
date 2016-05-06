namespace :queue do
  desc "Watch the queue, and print messages on the console"
  task watcher: :environment do
    config = YAML.load_file(Rails.root.join("config", "rabbitmq.yml"))[Rails.env].symbolize_keys

    conn = Bunny.new(config)
    conn.start

    ch = conn.create_channel
    ex = ch.topic(config[:exchange], passive: true)
    q = ch.queue("", exclusive: true)
    q.bind(ex, routing_key: '#')

    at_exit do
      puts "Closing channel"
      ch.close
      conn.close
    end

    puts "Listening for messages"
    q.subscribe(block: true) do |delivery_info, properties, payload|
      puts <<-EOT.strip_heredoc
        ----- New Message -----
        Routing_key: #{delivery_info.routing_key}
        Properties: #{properties.inspect}
        Payload: #{payload}
      EOT
    end
  end

  desc "Add published content items to the message queue, optionally specifying a limit on the number of items"
  task :requeue_content, [:number_of_items] => :environment do |_, args|
    RequeueContent.new(number_of_items: args[:number_of_items]).call
  end
end
