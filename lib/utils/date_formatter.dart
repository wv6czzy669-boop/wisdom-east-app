String formattedToday([DateTime? date]) {
  final value = date ?? DateTime.now();

  const months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];

  return "${months[value.month - 1]} ${value.day}, ${value.year}";
}
