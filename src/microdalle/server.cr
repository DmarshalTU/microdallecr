require "kemal"
require "http/client"
require "../../../openai/src/openai"


Log.setup_from_env

OPENAI_KEY = ""

  # Function to generate a save file name
  def generate_save_file_name(directory : String) : String
    current_time = Time.utc().to_s("%Y-%m-%d-%H:%M:%S%:z")
    random_string = Random::Secure.urlsafe_base64(8, padding: false)
    "#{directory}/#{current_time}-#{random_string}.jpg"
  end

  # Function to save a file
  def save_file(file_path : String, metadata : Hash, url : String)
    Log.info { "Saving file to #{file_path}" }
  
    # Download and save the image
    HTTP::Client.get(url) do |response|
      raise "Failed to download image" unless response.status_code == 200
      File.write(file_path, response.body_io)
    end
  
    # Save metadata as JSON
    metadata_json = metadata.to_json
    File.write("#{file_path}.json", metadata_json)
  
    Log.info { "File saved successfully #{file_path}" }
  end

  # Function to get save directory
  def get_save_dir : String?
    directory_env = ENV["SAVE_DIR"]?
    if directory_env
      Log.info { "Saving files to #{directory_env}" }
      directory_env
    else
      Log.info { "Do not save files" }
      nil
    end
  end

  save_dir = get_save_dir
  
  client = OpenAI::Client.new(OPENAI_KEY)

  # Define routes
  Kemal.config do |config|
    config.port = 8080 # Port number
  end

  # Generate route
  post "/generate" do |env|
    prompt = ""
    # Ensure the request body is not nil
    if body_io = env.request.body
      raw_body = body_io.gets_to_end

      begin
        body = JSON.parse(raw_body)
        prompt = body["prompt"].as_s
        Log.info { "Sending request to OpenAI with prompt: #{prompt}" }
        hd = body["hd"].as_s
        size = body["size"].as_s
        response = client.create_image_completion("dall-e-3", prompt, size, hd, 1)
        # Process and handle response
        url = response["data"][0]["url"].as_s

        # Background processing to save file
        if save_dir
          file_path = generate_save_file_name(save_dir)
          # Convert JSON::Any to Hash
          metadata = response.as_h
          spawn do
            begin
              save_file(file_path, metadata, url)
            rescue ex
              Log.error { "Failed to save file: #{ex.message}" }
            end
          end
        end

      response.to_json
      rescue ex
        env.response.status_code = 400
        { error: "Invalid JSON format: #{ex.message}" }.to_json
      end
    else
      env.response.status_code = 400
      { error: "No request body" }.to_json
    end
  end

  # Index route
  get "/" do |env|
    file_path = "./src/microdalle/public/index.html" # Updated path to index.html
  
    if File.exists?(file_path)
      file_content = File.read(file_path)
      env.response.content_type = "text/html"
      env.response.print file_content
    else
      Log.info { "Current directory: #{Dir.current}" }
      Log.info { "File not found: #{file_path}" }
      env.response.status_code = 404
      "File not found"
    end
  end
  

  # Start Kemal server
  Kemal.run