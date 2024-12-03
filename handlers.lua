
local json = require "json"


Handlers.add("UPDATE_PROFILE", "UPDATE_PROFILE", function(msg)
	if not msg.Tags.username or not msg.Tags.name then
		msg.reply({
			Data = json.encode({
				status = "error",
				message = "Required fields missing. Please provide username and name"
			})
		})
		return
	end
	local address = msg.From
	local username = msg.Tags.username
	local name = msg.Tags.name
	local description = msg.Tags.profileDescription or ""
	local extraData = msg.Tags.profileExtraData or "{}"
	local profilePicUrl = msg.Tags.profile_picture_url or ""
	local coverPhotoUrl = msg.Tags.cover_photo_url or ""
	if # username > 30 or not string.match(username, "^[A-Za-z0-9_]+$") then
		msg.reply({
			Data = json.encode({
				status = "error",
				message = "Invalid username. Must be 30 chars or less, containing only letters, numbers, and underscores"
			})
		})
		return
	end
	if # name > 50 or # description > 200 then
		msg.reply({
			Data = json.encode({
				status = "error",
				message = "Name must be 50 chars or less and description 200 chars or less"
			})
		})
		return
	end
	if # profilePicUrl > 200 or # coverPhotoUrl > 200 then
		msg.reply({
			Data = json.encode({
				status = "error",
				message = "URL length cannot exceed 200 characters"
			})
		})
		return
	end

	if not pcall(function()
		json.decode(extraData)
	end) then
		msg.reply({
			Data = json.encode({
				status = "error",
				message = "Invalid JSON format in profileExtraData"
			})
		})
		return
	end
	local results = admin:select('SELECT user_id FROM users WHERE address = ?;', {
		address
	})
	local success, err
	if # results > 0 then
		success, err = pcall(function()
			admin:apply([[UPDATE users 
                     SET username = ?, 
                         full_name = ?, 
                         description = ?,
                         profile_extra_data = ?,
                         profile_picture_url = ?,
                         cover_photo_url = ?
                        
                     WHERE address = ?;]], {
				username,
				name,
				description,
				extraData,
				profilePicUrl,
				coverPhotoUrl,
				address
			})
			print("stuffs updated!")
		end)

	else
		local currentTime = msg.Timestamp
		success, err = pcall(function()
			admin:apply([[INSERT INTO users 
                     (address, username, full_name, description, profile_extra_data, profile_picture_url, cover_photo_url, created_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?);]], {
				address,
				username,
				name,
				description,
				extraData,
				profilePicUrl,
				coverPhotoUrl,
				currentTime
			})
		end)
	end
	if success then
		local response = {
			status = "success",
			message = # results > 0 and "Profile updated successfully" or "Profile created successfully",
			data = {
				address = address,
				username = username,
				name = name,
				description = description,
				profile_extra_data = json.decode(extraData),
				profile_picture_url = profilePicUrl,
				cover_photo_url = coverPhotoUrl
			}
		}
		msg.reply({
			Data = json.encode(response)
		})
	else
		if string.find(err, "UNIQUE constraint failed: users.username") then
			msg.reply({
				Data = json.encode({
					status = "error",
					message = "Username already taken"
				})
			})
		elseif string.find(err, "UNIQUE constraint failed: users.address") then
			msg.reply({
				Data = json.encode({
					status = "error",
					message = "Address already registered"
				})
			})
		else
			msg.reply({
				Data = json.encode({
					status = "error",
					message = "Database error occurred. Please try again.",
					error = err
				})
			})
		end
	end
end)

Handlers.add(
   "SUBMIT_POST",
   "SUBMIT_POST",
   function(msg)
       -- Helper function to cleanup if something fails
       local function cleanupOnFailure(postId)
           if postId then
               admin:apply('DELETE FROM post_hashtags WHERE post_id = ?;', { postId })
               admin:apply('DELETE FROM posts WHERE post_id = ?;', { postId })
           end
       end

       if not msg.Tags.content then
           msg.reply({ Data = json.encode({
               status = "error",
               message = "Content is required"
           })})
           return
       end

       local address = msg.From
       local content = msg.Tags.content
       local mediaUrls = msg.Tags.media_urls or "[]"
       local postExtraData = msg.Tags.post_extra_data or "{}"
       local visibility = msg.Tags.visibility or "public"
       local postId = msg.Tags.post_id

       -- All validations...
       if #content > 2000 then
           msg.reply({ Data = json.encode({
               status = "error",
               message = "Content cannot exceed 2000 characters"
           })})
           return
       end

       -- Validate mediaUrls
       if mediaUrls ~= "[]" then
           local success, mediaList = pcall(json.decode, mediaUrls)
           if not success then
               msg.reply({ Data = json.encode({
                   status = "error",
                   message = "Invalid JSON format in media_urls. Expected format: [\"url1\", \"url2\"]"
               })})
               return
           end

           if type(mediaList) ~= "table" then
               msg.reply({ Data = json.encode({
                   status = "error",
                   message = "media_urls must be an array of URLs"
               })})
               return
           end

           for _, url in ipairs(mediaList) do
               if type(url) ~= "string" or
                  not string.match(url, "^https?://[%w-_%.%?%.:/%+=&]+$") or
                  #url > 200 then
                   msg.reply({ Data = json.encode({
                       status = "error",
                       message = "Invalid URL format or length in media_urls"
                   })})
                   return
               end
           end
       end

       -- Validate postExtraData
       if not pcall(function() json.decode(postExtraData) end) then
           msg.reply({ Data = json.encode({
               status = "error",
               message = "Invalid JSON format in post_extra_data"
           })})
           return
       end

       -- Extract hashtags
       local hashtags = {}
       for tag in content:gmatch("#(%w+)") do
           hashtags[#hashtags + 1] = tag:lower()
       end

       -- Verify user exists
       local userExists = admin:select('SELECT user_id FROM users WHERE address = ?;', { address })
       if #userExists == 0 then
           msg.reply({ Data = json.encode({
               status = "error",
               message = "User not found. Please create a profile first"
           })})
           return
       end

       local currentTime = msg.Timestamp
       local finalPostId
       local success, err = pcall(function()
           if postId then
               -- Check post ownership
               local postExists = admin:select('SELECT post_id FROM posts WHERE post_id = ? AND address = ?;', { postId, address })
               if #postExists == 0 then
                   error("Post not found or you're not authorized to edit it")
               end
               print("updating post..")

               -- Update post
               admin:apply(
                   [[UPDATE posts 
                     SET content = ?,
                         media_urls = ?,
                         post_extra_data = ?,
                         visibility = ?,
                         is_edited = 1,
                         updated_at = ?
                     WHERE post_id = ? AND address = ?;]],
                   {content, mediaUrls, postExtraData, visibility, currentTime, postId, address}
               )
               
               admin:apply('DELETE FROM post_hashtags WHERE post_id = ?;', { postId })
               finalPostId = postId
           else
               -- Create new post
               admin:apply(
                   [[INSERT INTO posts 
                     (address, content, media_urls, post_extra_data, visibility, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?);]],
                   {address, content, mediaUrls, postExtraData, visibility, currentTime, currentTime}
               )
                print("made new post!")
                local postResult = admin:select(
                    [[SELECT post_id FROM posts 
                    WHERE address = ? 
                    AND content = ? 
                    AND created_at = ?
                    ORDER BY post_id DESC LIMIT 1;]], 
                    {address, content, currentTime}
                )
                finalPostId = postResult[1].post_id
               print("Created new post with ID:", finalPostId)
           end

           -- Process hashtags
           for _, tag in ipairs(hashtags) do
               print("Processing hashtag:", tag)
               -- Insert hashtag
               admin:apply(
                   [[INSERT OR IGNORE INTO hashtags (name, created_at) 
                     VALUES (?, ?);]], 
                   {tag, currentTime}
               )
               
               -- Get hashtag_id using name
               local hashtagResult = admin:select('SELECT hashtag_id FROM hashtags WHERE name = ?;', { tag })
               if not hashtagResult[1] then
                   error("Failed to create hashtag: " .. tag)
               end
               
               print("Linking post_id:", finalPostId, "with hashtag_id:", hashtagResult[1].hashtag_id)
               
               -- Link hashtag to post
               admin:apply(
                   [[INSERT OR IGNORE INTO post_hashtags (post_id, hashtag_id) 
                     VALUES (?, ?);]],
                   {finalPostId, hashtagResult[1].hashtag_id}
               )
           end
       end)

       if not success then
           if not postId then
               cleanupOnFailure(finalPostId)
           end
           msg.reply({ Data = json.encode({
               status = "error",
               message = "Failed to " .. (postId and "update" or "create") .. " post",
               error = err
           })})
           return
       end

       -- Get final data for response
       local postData = admin:select('SELECT * FROM posts WHERE post_id = ?;', { finalPostId })[1]
       local postTags = admin:select([[
           SELECT h.name 
           FROM hashtags h 
           JOIN post_hashtags ph ON h.hashtag_id = ph.hashtag_id 
           WHERE ph.post_id = ?;
       ]], { finalPostId })
       
       local tagNames = {}
       for _, tag in ipairs(postTags) do
           table.insert(tagNames, tag.name)
       end

       msg.reply({ Data = json.encode({
           status = "success",
           message = postId and "Post updated successfully" or "Post created successfully",
           data = {
               post_id = postData.post_id,
               address = postData.address,
               content = postData.content,
               media_urls = json.decode(postData.media_urls),
               post_extra_data = json.decode(postData.post_extra_data),
               visibility = postData.visibility,
               is_edited = postData.is_edited,
               hashtags = tagNames,
               created_at = postData.created_at,
               updated_at = postData.updated_at
           }
       })})
   end
)

Handlers.add(
   "LIKE_POST",
   "LIKE_POST", 
   function(msg) -- Handler logic
       -- Validate required parameters
       if not msg.Tags.post_id then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Post ID is required"
               })
           })
           return
       end

       local address = msg.From
       local postId = msg.Tags.post_id
       print(address)
       print(postId)

       -- Get user_id from users table
       local userResult = admin:select('SELECT user_id FROM users WHERE address = ?;', { address })
       if #userResult == 0 then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "User not found. Please create a profile first"
               })
           })
           return
       end
       local userId = userResult[1].user_id

       -- Check if post exists
       local postExists = admin:select('SELECT post_id FROM posts WHERE post_id = ?;', { postId })
       if #postExists == 0 then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Post not found"
               })
           })
           return
       end

       -- Check if already liked
       local currentTime = msg.Timestamp
       local likeExists = admin:select('SELECT * FROM likes WHERE user_id = ? AND post_id = ?;', { userId, postId })
       
       local success, err = pcall(function()
           if #likeExists > 0 then
               -- Unlike: Remove the like
               admin:apply(
                   'DELETE FROM likes WHERE user_id = ? AND post_id = ?;',
                   { userId, postId }
               )
           else
               -- Like: Add new like
               admin:apply(
                   [[INSERT INTO likes (user_id, post_id, created_at)
                     VALUES (?, ?, ?);]],
                   { userId, postId, currentTime }
               )
           end
       end)

       if success then
           -- Get updated like count
           local likeCount = admin:select('SELECT COUNT(*) as count FROM likes WHERE post_id = ?;', { postId })[1].count

           msg.reply({
               Data = json.encode({
                   status = "success",
                   message = #likeExists > 0 and "Post unliked" or "Post liked",
                   data = {
                       post_id = postId,
                       user_id = userId,
                       action = #likeExists > 0 and "unlike" or "like",
                       like_count = likeCount
                   }
               })
           })
       else
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Failed to process like/unlike",
                   error = err
               })
           })
       end
   end
)

Handlers.add(
   "SUBMIT_COMMENT", -- Handler name
   "SUBMIT_COMMENT", -- Pattern matcher function
   function(msg) -- Handler logic
       -- Validate required parameters
       if not msg.Tags.post_id or not msg.Tags.content then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Post ID and content are required"
               })
           })
           return
       end

       local address = msg.From
       local postId = msg.Tags.post_id
       local content = msg.Tags.content
       local parentCommentId = msg.Tags.parent_comment_id  -- Optional, for replies
       local commentId = msg.Tags.comment_id  -- Optional, for editing
       
       -- Content length validation
       if #content > 1000 then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Comment content cannot exceed 1000 characters"
               })
           })
           return
       end

       -- Get user_id from address
       local userResult = admin:select('SELECT user_id FROM users WHERE address = ?;', { address })
       if #userResult == 0 then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "User not found. Please create a profile first"
               })
           })
           return
       end
       local userId = userResult[1].user_id

       -- Check if post exists
       local postExists = admin:select('SELECT post_id FROM posts WHERE post_id = ?;', { postId })
       if #postExists == 0 then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Post not found"
               })
           })
           return
       end

       -- If parent_comment_id is provided, verify it exists and belongs to the same post
       if parentCommentId then
           local parentComment = admin:select(
               'SELECT post_id FROM comments WHERE comment_id = ?;',
               { parentCommentId }
           )
           if #parentComment == 0 then
               msg.reply({
                   Data = json.encode({
                       status = "error",
                       message = "Parent comment not found"
                   })
               })
               return
           end
           if parentComment[1].post_id ~= postId then
               msg.reply({
                   Data = json.encode({
                       status = "error",
                       message = "Parent comment doesn't belong to the specified post"
                   })
               })
               return
           end
       end

       local currentTime = msg.Timestamp
       local success, err = pcall(function()
           if commentId then
               -- Editing existing comment
               local commentExists = admin:select(
                   'SELECT comment_id FROM comments WHERE comment_id = ? AND user_id = ?;',
                   { commentId, userId }
               )
               if #commentExists == 0 then
                   error("Comment not found or you're not authorized to edit it")
               end

               admin:apply(
                   [[UPDATE comments 
                     SET content = ?,
                         is_edited = 1,
                         updated_at = ?
                     WHERE comment_id = ? AND user_id = ?;]],
                   {content, currentTime, commentId, userId}
               )
           else
               -- Creating new comment
               admin:apply(
                   [[INSERT INTO comments 
                     (post_id, user_id, content, parent_comment_id, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?);]],
                   {postId, userId, content, parentCommentId, currentTime, currentTime}
               )
           end
       end)

       if success then
           -- Get the comment data for response
           local commentQuery = commentId and
               'SELECT * FROM comments WHERE comment_id = ?;' or
               'SELECT * FROM comments WHERE user_id = ? AND created_at = ? ORDER BY comment_id DESC LIMIT 1;'
           local commentParams = commentId and
               { commentId } or
               { userId, currentTime }
           
           local commentData = admin:select(commentQuery, commentParams)[1]

           msg.reply({
               Data = json.encode({
                   status = "success",
                   message = commentId and "Comment updated successfully" or "Comment created successfully",
                   data = {
                       comment_id = commentData.comment_id,
                       post_id = commentData.post_id,
                       user_id = commentData.user_id,
                       content = commentData.content,
                       parent_comment_id = commentData.parent_comment_id,
                       is_edited = commentData.is_edited,
                       created_at = commentData.created_at,
                       updated_at = commentData.updated_at
                   }
               })
           })
       else
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Failed to " .. (commentId and "update" or "create") .. " comment",
                   error = err
               })
           })
       end
   end
)

Handlers.add(
    "GET_PROFILES",
    "GET_PROFILES",
    function(msg)
        if not msg.Tags.addresses then
            msg.reply({
                Data = json.encode({
                    status = "error",
                    message = "Addresses list is required"
                })
            })
            return
        end

        -- Parse and validate addresses JSON
        local success, addresses = pcall(json.decode, msg.Tags.addresses)
        if not success or type(addresses) ~= "table" then
            msg.reply({
                Data = json.encode({
                    status = "error",
                    message = "Invalid JSON format for addresses. Expected format: [\"address1\", \"address2\"]"
                })
            })
            return
        end

        -- Check list length
        if #addresses > 100 then
            msg.reply({
                Data = json.encode({
                    status = "error",
                    message = "Cannot query more than 100 addresses"
                })
            })
            return
        end

        -- Create placeholders for IN clause
        local placeholders = table.concat(array_fill('?', #addresses), ',')
        local query = string.format('SELECT * FROM users WHERE address IN (%s);', placeholders)
        
        -- Get all users in one query
        local users = admin:select(query, addresses)
        
        -- Create results map
        local results = {}
        -- First, set null template for all requested addresses
        for _, address in ipairs(addresses) do
            results[address] = {
                user_id = nil,
                address = address,
                username = nil,
                full_name = nil,
                description = nil,
                profile_picture_url = nil,
                cover_photo_url = nil,
                profile_extra_data = nil,
                created_at = nil,
                updated_at = nil
            }
        end
        
        -- Then fill in existing user data
        for _, user in ipairs(users) do
            user.profile_extra_data = json.decode(user.profile_extra_data or '{}')
            results[user.address] = user
        end

        msg.reply({
            Data = json.encode({
                status = "success",
                data = results
            })
        })
    end
)

-- Helper function to create array of repeated values
function array_fill(value, count)
    local arr = {}
    for i = 1, count do
        arr[i] = value
    end
    return arr
end

Handlers.add(
   "GET_USERS",
   "GET_USERS",
   function(msg)
       local limit = tonumber(msg.Tags.limit) or 50  -- Default 50 if not specified
       local sortBy = msg.Tags.sortBy or "latest"    -- Default latest if not specified
       local cursor = msg.Tags.cursor                -- For pagination

       -- Validate limit
       if limit > 1000 then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Limit cannot exceed 1000"
               })
           })
           return
       end

       -- Construct the base query
       local query = 'SELECT * FROM users'
       local params = {}

       -- Add cursor condition if provided
       if cursor then
           if sortBy == "latest" then
               query = query .. ' WHERE user_id < ?'
           else
               query = query .. ' WHERE user_id > ?'
           end
           table.insert(params, cursor)
       end

       -- Add sorting
       query = query .. (sortBy == "latest" and ' ORDER BY user_id DESC' or ' ORDER BY user_id ASC')

       -- Add limit
       query = query .. ' LIMIT ?'
       table.insert(params, limit)

       -- Get users
       local users = admin:select(query, params)

       -- Parse JSON fields for each user
       for i, user in ipairs(users) do
           user.profile_extra_data = json.decode(user.profile_extra_data or '{}')
       end

       -- Get the next cursor
       local nextCursor = #users == limit and users[#users].user_id or nil
       msg.reply({
           Data = json.encode({
               status = "success",
               data = {
                   users = users,
                   next_cursor = nextCursor,
                   total_count = #users,
                   has_more = nextCursor ~= nil
               }
           })
       })
   end
)

