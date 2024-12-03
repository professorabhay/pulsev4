Handlers.add(
   "GET_PROFILE",
   "GET_PROFILE",
   function(msg)
       if not msg.Tags.address then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "Address is required"
               })
           })
           return
       end

       local address = msg.Tags.address

       -- Get user profile
       	local userResult = admin:select('SELECT * FROM users WHERE address = ?;', {
		address
	})

       if #userResult == 0 then
           msg.reply({
               Data = json.encode({
                   status = "error",
                   message = "User not found"
               })
           })
           return
       end

       -- Parse JSON fields
       local userData = userResult[1]
       userData.profile_extra_data = json.decode(userData.profile_extra_data or '{}')

       msg.reply({
           Data = json.encode({
               status = "success",
               data = userData
           })
       })
   end
)