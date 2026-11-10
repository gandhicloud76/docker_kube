$NumberOfVideos=30

if($NumberOfVideos -ge 20)
{

    "Greater or equal to 20"
}
else {
  "less than 20"  <# Action when all if and elseif conditions are false #>
}

$i=1
while($i -le 10)
{
    $i
    ++$i
}

for($i=1; $i -le 10; ++$i)
{
    $i
}

$CourseDetails= 'index', 'start', 'follow'

foreach ($course in $CourseDetails)
{
    $course
}