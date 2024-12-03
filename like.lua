Handlers.add(
   "LIKE_POST",
   "LIKE_POST", 
   function(msg) -- Handler logic
       -- Validate required parameters
       print("hello")
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