def get_confirmation(prompt="Continue? (y/n): "):
    """
    Prompts the user for confirmation (yes or no).

    Args:
        prompt (str): The confirmation prompt to display (default: "Continue? (y/n): ")

    Returns:
        bool: True if user confirms (yes), False otherwise.
    """
    while True:
        answer = input(prompt).lower()
        if answer in ["y", "yes"]:
            return True
        elif answer in ["n", "no"]:
            return False
        else:
            print("Invalid input. Please enter 'y' or 'n'.")
