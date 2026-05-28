{
    "Version":"2012-10-17",
    "Id": "PolicyForCloudFrontPrivateContent",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "${bucket_arn}/*",
            "Condition": {
                "ArnLike": {
                    "AWS:SourceArn": "${distribution_arn}"
                }
            }
        }
    ]
}
