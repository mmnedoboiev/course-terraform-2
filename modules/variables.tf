variable "bucket_prefix" {
  type        = string
  description = "Префікс імені бакета"
}

variable "enable_versioning" {
  type        = bool
  default     = false
  description = "Прапорець увімкнення версіонування"
}

variable "allowed_read_arns" {
  type        = list(string)
  default     = []
  description = "Перелік ARN (ролей/користувачів), яким дозволено читати з бакета"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Теги для ресурсів"
}