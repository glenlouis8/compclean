import Foundation

/// Said right before macOS shows its admin password box, so its "could not verify" warning isn't a surprise.
enum PasswordNote {
    static func text(doing action: String = "moves the files you picked to the Trash") -> String {
        """
        Next, macOS will ask for your password, because some of these files belong to the whole Mac, \
        not just your account. The box comes from macOS, so Suds never sees your password. \
        It may say Apple "could not verify" the script. That's only because Suds isn't signed \
        with a paid Apple developer account. Suds still only \(action).
        """
    }
}
