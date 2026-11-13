const response = await fetch(
  `http://127.0.0.1:${process.env.PORT ?? "3000"}/health/ready`,
);

if (!response.ok) process.exit(1);
